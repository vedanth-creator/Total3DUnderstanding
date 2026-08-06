import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient

from service.app import REMOTE_TRAINING_ENVIRONMENT_VARIABLES, create_app
from service.reconstruction import FakeReconstructionProcessor
from service.remote_reconstruction import RemoteTrainingReconstructionProcessor
from service.training_orchestrator import TrainingOrchestrator


REMOTE_ENVIRONMENT = {
    variable_name: "configured-for-test"
    for variable_name in REMOTE_TRAINING_ENVIRONMENT_VARIABLES
}


class ApplicationWiringTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.storage_root = Path(self.temporary_directory.name) / "storage"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_missing_remote_environment_uses_fake_processor(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch(
            "service.app.RemoteTrainingReconstructionProcessor"
        ) as remote_processor:
            application = create_app(storage_root=self.storage_root)
            with TestClient(application):
                self.assertIsInstance(
                    application.state.reconstruction_processor,
                    FakeReconstructionProcessor,
                )

        remote_processor.assert_not_called()
        self.assertIsNone(application.state.training_orchestrator)

    def test_complete_remote_environment_uses_remote_processor(self) -> None:
        artifact_storage = object()
        gpu_job_provider = object()

        with mock.patch.dict(os.environ, REMOTE_ENVIRONMENT, clear=True), mock.patch(
            "service.app.S3CompatibleArtifactStorage.from_environment",
            return_value=artifact_storage,
        ) as storage_factory, mock.patch(
            "service.app.RunPodGPUJobProvider.from_environment",
            return_value=gpu_job_provider,
        ) as provider_factory:
            application = create_app(storage_root=self.storage_root)
            processor = application.state.reconstruction_processor
            orchestrator = application.state.training_orchestrator
            self.assertIsInstance(
                processor,
                RemoteTrainingReconstructionProcessor,
            )
            self.assertIsInstance(orchestrator, TrainingOrchestrator)
            with mock.patch.object(
                processor,
                "resume_incomplete",
                wraps=processor.resume_incomplete,
            ) as resume_incomplete, mock.patch.object(
                processor,
                "shutdown",
                wraps=processor.shutdown,
            ) as shutdown, mock.patch.object(
                orchestrator,
                "reconcile_once",
                wraps=orchestrator.reconcile_once,
            ) as reconcile_once, TestClient(application):
                self.assertIs(
                    application.state.reconstruction_processor,
                    processor,
                )
                self.assertIs(
                    application.state.training_orchestrator,
                    orchestrator,
                )

        storage_factory.assert_called_once_with()
        provider_factory.assert_called_once_with()
        self.assertIs(orchestrator.storage, artifact_storage)
        self.assertIs(orchestrator.provider, gpu_job_provider)
        self.assertEqual(orchestrator.maximum_iterations, 30000)
        self.assertEqual(orchestrator.stale_after_seconds, 28800)
        self.assertIs(processor.training, orchestrator)
        self.assertEqual(processor.storage_root, self.storage_root.resolve())
        self.assertEqual(
            processor.reconstruction_jobs_root,
            Path("reconstruction/jobs").resolve(),
        )
        resume_incomplete.assert_called_once_with()
        self.assertEqual(reconcile_once.call_count, 2)
        shutdown.assert_called_once_with()

    def test_explicit_processor_overrides_remote_environment(self) -> None:
        processor = mock.Mock()

        with mock.patch.dict(os.environ, REMOTE_ENVIRONMENT, clear=True), mock.patch(
            "service.app.S3CompatibleArtifactStorage.from_environment"
        ) as storage_factory, mock.patch(
            "service.app.RemoteTrainingReconstructionProcessor"
        ) as remote_processor:
            application = create_app(
                storage_root=self.storage_root,
                reconstruction_processor=processor,
            )
            with TestClient(application):
                self.assertIs(
                    application.state.reconstruction_processor,
                    processor,
                )

        storage_factory.assert_not_called()
        remote_processor.assert_not_called()
        processor.resume_incomplete.assert_called_once_with()
        processor.shutdown.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
