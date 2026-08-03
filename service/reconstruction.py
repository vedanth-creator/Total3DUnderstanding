"""Bounded fake reconstruction worker for the first upload milestone."""

from concurrent.futures import Future, ThreadPoolExecutor
import threading
import time
from typing import Dict, Tuple

from service.api_schemas import JobStatus
from service.job_repository import FileJobRepository


class FakeReconstructionProcessor:
    STAGES: Tuple[Tuple[float, str], ...] = (
        (0.12, "preparing_video"),
        (0.28, "extracting_key_frames"),
        (0.48, "estimating_camera_motion"),
        (0.68, "reconstructing_room_geometry"),
        (0.86, "identifying_walls_and_furniture"),
        (0.97, "preparing_editable_workspace"),
    )

    def __init__(
        self,
        repository: FileJobRepository,
        stage_delay_seconds: float = 0.55,
        maximum_workers: int = 2,
        auto_process: bool = True,
    ) -> None:
        if stage_delay_seconds < 0 or maximum_workers <= 0:
            raise ValueError("Processor delay and worker count are invalid.")
        self.repository = repository
        self.stage_delay_seconds = stage_delay_seconds
        self.auto_process = auto_process
        self._executor = ThreadPoolExecutor(
            max_workers=maximum_workers,
            thread_name_prefix="room-scan",
        )
        self._lock = threading.Lock()
        self._futures: Dict[str, Future] = {}

    def submit(self, job_id: str) -> None:
        if not self.auto_process:
            return
        with self._lock:
            current = self._futures.get(job_id)
            if current is not None and not current.done():
                return
            self._futures[job_id] = self._executor.submit(self.process, job_id)

    def resume_incomplete(self) -> None:
        for job in self.repository.list_jobs():
            if job.status in (JobStatus.QUEUED, JobStatus.PROCESSING):
                self.submit(job.job_id)

    def process(self, job_id: str) -> None:
        try:
            for progress, stage in self.STAGES:
                self.repository.update(
                    job_id,
                    status=JobStatus.PROCESSING,
                    progress=progress,
                    stage=stage,
                )
                if self.stage_delay_seconds:
                    time.sleep(self.stage_delay_seconds)
            self.repository.update(
                job_id,
                status=JobStatus.COMPLETED,
                progress=1.0,
                stage="completed",
            )
        except Exception as error:
            try:
                self.repository.update(
                    job_id,
                    status=JobStatus.FAILED,
                    progress=0.0,
                    stage="failed",
                    error="Fake reconstruction failed: %s" % error,
                )
            except Exception:
                pass

    def shutdown(self) -> None:
        self._executor.shutdown(wait=False, cancel_futures=True)
