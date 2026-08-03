import tempfile
import time
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from service.api_schemas import ClientScanMetadata, JobStatus
from service.app import create_app
from service.job_repository import FileJobRepository
from service.reconstruction import FakeReconstructionProcessor
from service.upload_storage import LocalUploadStorage


VIDEO_BYTES = b"small-deterministic-video-payload"


class RoomScanAPITest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.storage_root = Path(self.temporary_directory.name) / "storage"
        self.repository = FileJobRepository(self.storage_root / "jobs")
        self.upload_storage = LocalUploadStorage(self.storage_root)
        self.processor = FakeReconstructionProcessor(
            self.repository,
            stage_delay_seconds=0,
            auto_process=False,
        )
        self.client_context = TestClient(
            create_app(
                storage_root=self.storage_root,
                job_repository=self.repository,
                upload_storage=self.upload_storage,
                reconstruction_processor=self.processor,
            )
        )
        self.client = self.client_context.__enter__()

    def tearDown(self) -> None:
        self.client_context.__exit__(None, None, None)
        self.temporary_directory.cleanup()

    def upload(
        self,
        data: bytes = VIDEO_BYTES,
        filename: str = "scan.mov",
        content_type: str = "video/quicktime",
    ):
        return self.client.post(
            "/v1/room-scans",
            files={"video": (filename, data, content_type)},
            data={
                "duration_seconds": "24.5",
                "width": "1920",
                "height": "1080",
                "source": "recorded",
                "client_scan_id": "client-scan-123",
            },
        )

    def test_successful_video_upload_returns_accepted_job(self) -> None:
        response = self.upload()

        self.assertEqual(response.status_code, 202)
        payload = response.json()
        self.assertEqual(payload["status"], "queued")
        self.assertEqual(
            payload["status_url"],
            "/v1/room-scans/%s" % payload["job_id"],
        )
        job = self.repository.get(payload["job_id"])
        self.assertIsNotNone(job)
        assert job is not None
        self.assertEqual(job.client_metadata.duration_seconds, 24.5)
        self.assertEqual(job.client_metadata.client_scan_id, "client-scan-123")

    def test_rejects_unsupported_extension_or_content_type(self) -> None:
        cases = (
            ("scan.avi", "video/x-msvideo"),
            ("scan.mov", "text/plain"),
            ("scan.mp4", "video/quicktime"),
        )
        for filename, content_type in cases:
            with self.subTest(filename=filename, content_type=content_type):
                response = self.upload(filename=filename, content_type=content_type)
                self.assertEqual(response.status_code, 422)

    def test_rejects_empty_upload(self) -> None:
        response = self.upload(data=b"")

        self.assertEqual(response.status_code, 422)
        self.assertIn("must not be empty", response.json()["detail"])

    def test_rejects_oversized_upload(self) -> None:
        small_storage = LocalUploadStorage(
            self.storage_root,
            maximum_upload_bytes=4,
            chunk_size=2,
        )
        processor = FakeReconstructionProcessor(
            self.repository,
            stage_delay_seconds=0,
            auto_process=False,
        )
        with TestClient(
            create_app(
                storage_root=self.storage_root,
                job_repository=self.repository,
                upload_storage=small_storage,
                reconstruction_processor=processor,
            )
        ) as client:
            response = client.post(
                "/v1/room-scans",
                files={"video": ("scan.mp4", b"12345", "video/mp4")},
            )

        self.assertEqual(response.status_code, 413)

    def test_unknown_job_returns_not_found(self) -> None:
        unknown = "00000000-0000-0000-0000-000000000000"

        response = self.client.get("/v1/room-scans/%s" % unknown)

        self.assertEqual(response.status_code, 404)

    def test_job_endpoint_returns_queued_processing_and_completed_states(self) -> None:
        job_id = self.upload().json()["job_id"]

        queued = self.client.get("/v1/room-scans/%s" % job_id).json()
        self.assertEqual(queued["status"], "queued")
        self.assertEqual(queued["progress"], 0.0)

        self.repository.update(
            job_id,
            JobStatus.PROCESSING,
            0.5,
            "estimating_camera_motion",
        )
        processing = self.client.get("/v1/room-scans/%s" % job_id).json()
        self.assertEqual(processing["status"], "processing")
        self.assertEqual(processing["progress"], 0.5)
        self.assertEqual(processing["stage"], "estimating_camera_motion")

        self.repository.update(job_id, JobStatus.COMPLETED, 1.0, "completed")
        completed = self.client.get("/v1/room-scans/%s" % job_id).json()
        self.assertEqual(completed["status"], "completed")

    def test_scene_requested_before_completion_returns_conflict(self) -> None:
        job_id = self.upload().json()["job_id"]

        response = self.client.get("/v1/room-scans/%s/scene" % job_id)

        self.assertEqual(response.status_code, 409)

    def test_completed_job_returns_normalized_sample_scene(self) -> None:
        job_id = self.upload().json()["job_id"]
        self.repository.update(job_id, JobStatus.COMPLETED, 1.0, "completed")

        response = self.client.get("/v1/room-scans/%s/scene" % job_id)

        self.assertEqual(response.status_code, 200)
        scene = response.json()
        self.assertEqual(scene["schema_version"], "1.0")
        self.assertEqual(scene["coordinate_system"]["units"], "meters")
        self.assertEqual(scene["objects"][0]["category"]["name"], "sofa")
        self.assertTrue(any("sample geometry" in warning for warning in scene["warnings"]))

    def test_server_generates_safe_filename_and_saves_exact_bytes(self) -> None:
        response = self.upload(filename="../../user-controlled.mov")
        job_id = response.json()["job_id"]
        expected = self.storage_root / "uploads" / job_id / "room-video.mov"

        self.assertEqual(response.status_code, 202)
        self.assertTrue(expected.is_file())
        self.assertEqual(expected.read_bytes(), VIDEO_BYTES)
        self.assertNotIn("user-controlled", str(expected))

    def test_job_metadata_survives_repository_reload(self) -> None:
        job_id = self.upload().json()["job_id"]
        self.repository.update(
            job_id,
            JobStatus.PROCESSING,
            0.68,
            "reconstructing_room_geometry",
        )

        reloaded = FileJobRepository(self.storage_root / "jobs").get(job_id)

        self.assertIsNotNone(reloaded)
        assert reloaded is not None
        self.assertEqual(reloaded.status, JobStatus.PROCESSING)
        self.assertEqual(reloaded.progress, 0.68)
        self.assertEqual(reloaded.upload_size_bytes, len(VIDEO_BYTES))

    def test_fake_processor_completes_using_bounded_stage_sequence(self) -> None:
        processor = FakeReconstructionProcessor(
            self.repository,
            stage_delay_seconds=0.002,
            maximum_workers=1,
            auto_process=True,
        )
        with TestClient(
            create_app(
                storage_root=self.storage_root,
                job_repository=self.repository,
                upload_storage=self.upload_storage,
                reconstruction_processor=processor,
            )
        ) as client:
            response = client.post(
                "/v1/room-scans",
                files={"video": ("scan.m4v", VIDEO_BYTES, "video/x-m4v")},
            )
            job_id = response.json()["job_id"]
            deadline = time.monotonic() + 2.0
            payload = client.get("/v1/room-scans/%s" % job_id).json()
            while payload["status"] != "completed" and time.monotonic() < deadline:
                time.sleep(0.01)
                payload = client.get("/v1/room-scans/%s" % job_id).json()

        self.assertEqual(payload["status"], "completed")
        self.assertEqual(payload["progress"], 1.0)
        self.assertEqual(payload["stage"], "completed")


if __name__ == "__main__":
    unittest.main()
