import io
import json
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest import mock
from uuid import uuid4
from fastapi.testclient import TestClient

from gpu_worker.worker import (
    INDOOR_ROOM_SPLATFACTO_PRESET,
    InvalidDatasetError,
    TrainingError,
    build_splatfacto_training_command,
    execute_training,
    prepare_portable_training_archive,
    safe_extract,
    validate_dataset,
)
from service.api_schemas import ClientScanMetadata
from service.artifact_storage import ArtifactStorageError, LocalArtifactStorage, S3CompatibleArtifactStorage
from service.gpu_jobs import GPUJob, GPUJobState, RunPodGPUJobProvider
from service.job_repository import FileJobRepository
from service.app import create_app
from service.reconstruction import FakeReconstructionProcessor
from service.upload_storage import LocalUploadStorage
from service.training_orchestrator import TrainingOrchestrator
from service.training_state import InvalidTrainingTransition, TrainingStage, transition_training_job


class FakeS3Error(Exception):
    def __init__(self, code):
        self.response = {"Error": {"Code": code}}


class FakeS3:
    def __init__(self):
        self.calls = []
        self.exists = True
    def __getattr__(self, name):
        def call(*args, **kwargs):
            self.calls.append((name, args, kwargs))
            if name == "generate_presigned_url":
                return "https://signed.example/" + kwargs["Params"]["Key"]
            if name == "head_object" and not self.exists:
                raise FakeS3Error("404")
        return call


class FakeProvider:
    def __init__(self):
        self.submissions = []
        self.job = GPUJob("gpu-1", GPUJobState.QUEUED)
        self.cancelled = []
    def submit_training_job(self, payload):
        self.submissions.append(payload)
        return "gpu-1"
    def get_training_job(self, provider_job_id):
        return self.job
    def cancel_training_job(self, provider_job_id):
        self.cancelled.append(provider_job_id)


class RemoteTrainingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.portable_archive_patcher = mock.patch(
            "gpu_worker.worker.prepare_portable_training_archive",
            self._fake_prepare_portable_training_archive,
        )
        self.portable_archive_patcher.start()
    def tearDown(self):
        self.portable_archive_patcher.stop()
        self.temp.cleanup()

    def test_local_storage_round_trip_and_key_validation(self):
        storage = LocalArtifactStorage(self.root / "objects")
        source = self.root / "source.bin"
        source.write_bytes(b"artifact")
        storage.upload_file(source, "jobs/one/file.bin")
        target = self.root / "download.bin"
        storage.download_file("jobs/one/file.bin", target)
        self.assertEqual(target.read_bytes(), b"artifact")
        self.assertTrue(storage.object_exists("jobs/one/file.bin"))
        self.assertTrue(storage.create_download_url("jobs/one/file.bin").startswith("file:"))
        storage.delete_object("jobs/one/file.bin")
        self.assertFalse(storage.object_exists("jobs/one/file.bin"))
        with self.assertRaises(ArtifactStorageError):
            storage.create_upload_url("../escape")

    def test_mocked_s3_operations_and_urls(self):
        client = FakeS3()
        storage = S3CompatibleArtifactStorage(client, "bucket", "prefix")
        source = self.root / "x"
        source.write_bytes(b"x")
        storage.upload_file(source, "job/x")
        self.assertIn("prefix/job/x", storage.create_upload_url("job/x"))
        self.assertTrue(storage.object_exists("job/x"))
        client.exists = False
        self.assertFalse(storage.object_exists("job/x"))

    def test_runpod_request_and_response_mapping(self):
        responses = iter((
            {"id": "rp-1"},
            {"id": "rp-1", "status": "IN_PROGRESS", "progress": {"progress": 0.7, "stage": "training"}},
            {},
        ))
        class Response:
            def __init__(self, payload): self.payload = payload
            def __enter__(self): return self
            def __exit__(self, *args): return None
            def read(self): return json.dumps(self.payload).encode()
        requests = []
        def opener(request, timeout):
            requests.append(request)
            return Response(next(responses))
        provider = RunPodGPUJobProvider("endpoint", "secret", opener=opener)
        self.assertEqual(provider.submit_training_job({"room_scan_id": "x"}), "rp-1")
        job = provider.get_training_job("rp-1")
        self.assertEqual(job.state, GPUJobState.RUNNING)
        self.assertEqual(job.progress, 0.7)
        provider.cancel_training_job("rp-1")
        self.assertNotIn("secret", repr(requests[0].data))

    def _repository_job(self):
        repository = FileJobRepository(self.root / "jobs")
        job_id = str(uuid4())
        return repository, repository.create(job_id, "uploads/video.mov", 10, ClientScanMetadata())

    def test_state_transitions_are_validated_and_idempotent(self):
        _, job = self._repository_job()
        queued = transition_training_job(job, TrainingStage.QUEUED_FOR_GPU, 0.4)
        same = transition_training_job(queued, TrainingStage.QUEUED_FOR_GPU, 0.3)
        self.assertEqual(same.progress, 0.4)
        completed = transition_training_job(queued, TrainingStage.COMPLETED, 1)
        with self.assertRaises(InvalidTrainingTransition):
            transition_training_job(completed, TrainingStage.TRAINING, 0.7)

    def test_duplicate_submission_and_successful_reconciliation(self):
        repository, job = self._repository_job()
        storage = LocalArtifactStorage(self.root / "objects")
        provider = FakeProvider()
        archive = self.root / "dataset.tar.gz"
        archive.write_bytes(b"data")
        orchestrator = TrainingOrchestrator(repository, storage, provider)
        first = orchestrator.submit_prepared_dataset(job.job_id, archive)
        second = orchestrator.submit_prepared_dataset(job.job_id, archive)
        self.assertEqual(first.provider_job_id, second.provider_job_id)
        self.assertEqual(len(provider.submissions), 1)
        keys = orchestrator.artifact_keys(job.job_id)
        artifact = self.root / "artifact"
        artifact.write_bytes(b"ok")
        for name in ("splat", "training_archive", "log", "result_manifest"):
            storage.upload_file(artifact, keys[name])
        provider.job = GPUJob("gpu-1", GPUJobState.COMPLETED, output={"status": "completed", "duration_seconds": 12})
        orchestrator.reconcile_once()
        completed = repository.get(job.job_id)
        self.assertEqual(completed.stage, "completed")
        self.assertTrue(completed.to_dict()["training"]["viewer_ready"])

    def test_archive_traversal_and_missing_dataset_files_are_rejected(self):
        archive = self.root / "bad.tar.gz"
        with tarfile.open(archive, "w:gz") as handle:
            info = tarfile.TarInfo("../escape")
            info.size = 1
            handle.addfile(info, io.BytesIO(b"x"))
        with self.assertRaises(InvalidDatasetError):
            safe_extract(archive, self.root / "out", 100)
        dataset = self.root / "dataset"
        dataset.mkdir()
        with self.assertRaisesRegex(InvalidDatasetError, "transforms"):
            validate_dataset(dataset)
        (dataset / "transforms.json").write_text('{"frames": []}')
        with self.assertRaisesRegex(InvalidDatasetError, "sparse_pc"):
            validate_dataset(dataset)

    def _worker_payload(self):
        return {"schema_version": "1.0", "room_scan_id": "scan", "dataset_download_url": "https://download", "artifact_upload_urls": {name: "https://upload/" + name for name in ("splat", "training_archive", "log", "result_manifest")}, "requested_method": "splatfacto", "maximum_iterations": 2, "correlation_id": "correlation"}

    @staticmethod
    def _fake_download(url, destination, maximum):
        del url, maximum
        build = destination.parent / "build-dataset"
        build.mkdir()
        (build / "images").mkdir()
        (build / "images" / "a.png").write_bytes(b"png")
        (build / "sparse_pc.ply").write_text("ply\n")
        identity = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        (build / "transforms.json").write_text(json.dumps({"fl_x": 1, "fl_y": 1, "cx": 1, "cy": 1, "w": 2, "h": 2, "frames": [{"file_path": "images/a.png", "transform_matrix": identity}]}))
        with tarfile.open(destination, "w:gz") as handle:
            handle.add(build, arcname="nerfstudio-data")

    @staticmethod
    def _fake_prepare_portable_training_archive(run_directory, staging_root):
        portable_run = staging_root / "training" / "room-scan" / "splatfacto" / "run"
        shutil.copytree(run_directory, portable_run)
        return portable_run

    def test_worker_success_and_command_failures(self):
        uploads = []
        uploaded_archive = self.root / "uploaded-training.tar.gz"
        uploaded_log = self.root / "uploaded-training.log"
        def fake_run(arguments, log, cwd, timeout):
            del log, cwd, timeout
            if arguments[0] == "ns-train":
                output = Path(arguments[arguments.index("--output-dir") + 1]) / "run"
                output.mkdir(parents=True)
                (output / "config.yml").write_text("config")
                (output / "nerfstudio_models").mkdir()
                (output / "nerfstudio_models" / "step.ckpt").write_bytes(b"checkpoint")
            else:
                export = Path(arguments[arguments.index("--output-dir") + 1])
                (export / "splat.ply").write_bytes(b"splat")
        def capture_upload(url, path):
            uploads.append((url, path.name))
            if url.endswith("/training_archive"):
                shutil.copy2(path, uploaded_archive)
            if url.endswith("/log"):
                shutil.copy2(path, uploaded_log)
        with mock.patch("gpu_worker.worker.download", self._fake_download), mock.patch("gpu_worker.worker.run_command", fake_run), mock.patch("gpu_worker.worker.upload", capture_upload):
            result = execute_training(self._worker_payload())
        self.assertEqual(result["status"], "completed")
        self.assertEqual(len(uploads), 4)
        extracted_archive = self.root / "extracted-training"
        extracted_archive.mkdir()
        with tarfile.open(uploaded_archive, "r:gz") as handle:
            handle.extractall(extracted_archive)
        run = extracted_archive / "training" / "room-scan" / "splatfacto" / "run"
        self.assertTrue((run / "config.yml").is_file())
        self.assertTrue(any((run / "nerfstudio_models").glob("*.ckpt")))
        self.assertTrue((extracted_archive / "export" / "splat.ply").is_file())
        self.assertTrue((extracted_archive / "dataset" / "transforms.json").is_file())
        structured_logs = [json.loads(line) for line in uploaded_log.read_text().splitlines()]
        training_log = next(item for item in structured_logs if item.get("event") == "splatfacto_training_command")
        self.assertEqual(training_log["preset"], INDOOR_ROOM_SPLATFACTO_PRESET)
        self.assertIn("--pipeline.model.use-scale-regularization", training_log["command"])

        for failing_command in ("ns-train", "ns-export"):
            def fail(arguments, log, cwd, timeout, target=failing_command):
                if arguments[0] == target:
                    raise TrainingError("failed " + target)
                fake_run(arguments, log, cwd, timeout)
            with mock.patch("gpu_worker.worker.download", self._fake_download), mock.patch("gpu_worker.worker.run_command", fail), mock.patch("gpu_worker.worker.upload", lambda url, path: None):
                result = execute_training(self._worker_payload())
            self.assertEqual(result["status"], "failed")
            self.assertEqual(result["failure_reason"], "training_failure")

    def test_indoor_room_splatfacto_preset_uses_pinned_supported_options(self):
        command = build_splatfacto_training_command(
            Path("/dataset"),
            Path("/output"),
            12_345,
        )
        arguments = dict(zip(command[2::2], command[3::2]))

        self.assertEqual(command[:2], ["ns-train", "splatfacto"])
        self.assertEqual(arguments["--max-num-iterations"], "12345")
        self.assertEqual(arguments["--pipeline.datamanager.train-cameras-sampling-strategy"], "fps")
        self.assertEqual(arguments["--pipeline.model.use-scale-regularization"], "True")
        self.assertEqual(arguments["--pipeline.model.max-gauss-ratio"], "5.0")
        self.assertEqual(arguments["--pipeline.model.cull-scale-thresh"], "0.15")
        self.assertEqual(arguments["--pipeline.model.cull-alpha-thresh"], "0.15")
        self.assertEqual(arguments["--pipeline.model.densify-grad-thresh"], "0.001")
        self.assertEqual(arguments["--pipeline.model.camera-optimizer.mode"], "off")

    def test_portable_archive_staging_rewrites_viewer_paths(self):
        run = self.root / "source-run"
        dataset = self.root / "source-dataset"
        exports = self.root / "source-export"
        (run / "nerfstudio_models").mkdir(parents=True)
        (run / "config.yml").write_text("saved-config")
        (run / "nerfstudio_models" / "step.ckpt").write_bytes(b"checkpoint")
        dataset.mkdir()
        (dataset / "transforms.json").write_text("{}")
        exports.mkdir()
        (exports / "splat.ply").write_bytes(b"splat")

        dataparser = SimpleNamespace(data=self.root / "old-data")
        datamanager = SimpleNamespace(data=self.root / "old-data", dataparser=dataparser)
        config = SimpleNamespace(
            output_dir=self.root / "old-output",
            experiment_name="old-experiment",
            method_name="splatfacto",
            timestamp="old-run",
            data=self.root / "old-data",
            pipeline=SimpleNamespace(datamanager=datamanager),
        )
        fake_yaml = ModuleType("yaml")
        fake_yaml.Loader = object
        fake_yaml.load = lambda contents, Loader: config
        fake_yaml.dump = lambda value: "portable-config"
        staging = self.root / "staging"
        with mock.patch.dict(sys.modules, {"yaml": fake_yaml}):
            portable_run = prepare_portable_training_archive(run, staging)

        self.assertEqual(portable_run, staging / "training" / "room-scan" / "splatfacto" / "run")
        self.assertEqual(config.output_dir, Path("training"))
        self.assertEqual(config.data, Path("dataset"))
        self.assertEqual(config.pipeline.datamanager.data, Path("dataset"))
        self.assertEqual(config.pipeline.datamanager.dataparser.data, Path("dataset"))
        self.assertEqual((portable_run / "config.yml").read_text(), "portable-config")
        self.assertTrue((portable_run / "nerfstudio_models" / "step.ckpt").is_file())

    def test_artifact_upload_failure_is_structured(self):
        def successful_commands(arguments, log, cwd, timeout):
            del log, cwd, timeout
            output = Path(arguments[arguments.index("--output-dir") + 1])
            if arguments[0] == "ns-train":
                run = output / "run"
                run.mkdir(parents=True)
                (run / "config.yml").write_text("config")
                (run / "nerfstudio_models").mkdir()
                (run / "nerfstudio_models" / "step.ckpt").write_bytes(b"checkpoint")
            else:
                (output / "splat.ply").write_bytes(b"splat")
        with mock.patch("gpu_worker.worker.download", self._fake_download), mock.patch("gpu_worker.worker.run_command", successful_commands), mock.patch("gpu_worker.worker.upload", side_effect=RuntimeError("storage unavailable")):
            result = execute_training(self._worker_payload())
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["failure_reason"], "infrastructure_failure")

    def test_fastapi_status_remains_compatible_and_artifacts_are_signed(self):
        repository, job = self._repository_job()
        storage = LocalArtifactStorage(self.root / "objects")
        provider = FakeProvider()
        orchestrator = TrainingOrchestrator(repository, storage, provider)
        artifact = self.root / "splat.ply"
        artifact.write_bytes(b"splat")
        key = orchestrator.artifact_keys(job.job_id)["splat"]
        storage.upload_file(artifact, key)
        from dataclasses import replace
        repository.save(replace(job, splat_object_key=key))
        processor = FakeReconstructionProcessor(repository, auto_process=False)
        with TestClient(create_app(storage_root=self.root / "api", job_repository=repository, upload_storage=LocalUploadStorage(self.root / "api"), reconstruction_processor=processor, training_orchestrator=orchestrator)) as client:
            status = client.get("/v1/room-scans/%s" % job.job_id).json()
            self.assertEqual(status["job_id"], job.job_id)
            self.assertIn("status", status)
            self.assertIn("training", status)
            response = client.get("/v1/room-scans/%s/artifacts/splat" % job.job_id, follow_redirects=False)
            self.assertEqual(response.status_code, 307)
            self.assertTrue(response.headers["location"].startswith("file:"))


if __name__ == "__main__":
    unittest.main()
