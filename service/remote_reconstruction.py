"""Local COLMAP-to-dataset pipeline that hands work to durable GPU training."""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
from typing import Optional

from reconstruction.config import ReconstructionConfig
from reconstruction.nerfstudio_dataset import NerfstudioDatasetPreparer
from reconstruction.worker import ColmapReconstructionWorker
from service.job_repository import FileJobRepository
from service.training_orchestrator import TrainingOrchestrator
from service.training_state import TrainingStage, transition_training_job


class RemoteTrainingReconstructionProcessor:
    def __init__(self, repository: FileJobRepository, storage_root: Path, reconstruction_jobs_root: Path, training: TrainingOrchestrator, reconstruction_worker: Optional[ColmapReconstructionWorker] = None, dataset_preparer: Optional[NerfstudioDatasetPreparer] = None, maximum_workers: int = 1) -> None:
        self.repository = repository
        self.storage_root = storage_root.resolve()
        self.reconstruction_jobs_root = reconstruction_jobs_root.resolve()
        self.training = training
        self.worker = reconstruction_worker or ColmapReconstructionWorker()
        self.preparer = dataset_preparer or NerfstudioDatasetPreparer()
        self.executor = ThreadPoolExecutor(max_workers=maximum_workers, thread_name_prefix="room-colmap")

    def submit(self, job_id: str) -> None:
        job = self.repository.get(job_id)
        if job is None or job.provider_job_id or job.stage in {"completed", "failed", "cancelled"}:
            return
        self.executor.submit(self.process, job_id)

    def resume_incomplete(self) -> None:
        self.training.reconcile_once()
        for job in self.repository.list_jobs():
            if not job.provider_job_id and job.stage not in {"completed", "failed", "cancelled"}:
                self.submit(job.job_id)

    def process(self, job_id: str) -> None:
        job = self.repository.get(job_id)
        if job is None:
            return
        try:
            archive = self.reconstruction_jobs_root / job_id / "nerfstudio-data.tar.gz"
            if not archive.is_file():
                reconstructing = transition_training_job(job, TrainingStage.RECONSTRUCTING, 0.1)
                self.repository.save(reconstructing)
                video = (self.storage_root / job.upload_relative_path).resolve()
                if self.storage_root not in video.parents or not video.is_file():
                    raise RuntimeError("Room-scan upload is missing.")
                result_path = self.reconstruction_jobs_root / job_id / "reconstruction.json"
                reconstruction_complete = False
                if result_path.is_file():
                    try:
                        reconstruction_complete = json.loads(result_path.read_text()).get("status") == "completed"
                    except (OSError, json.JSONDecodeError):
                        reconstruction_complete = False
                job_workspace = self.reconstruction_jobs_root / job_id
                if job_workspace.exists() and not reconstruction_complete:
                    recovery = self.reconstruction_jobs_root / (".interrupted-%s-%s" % (job_id, os.getpid()))
                    os.replace(str(job_workspace), str(recovery))
                if not reconstruction_complete:
                    self.worker.run(ReconstructionConfig(job_id=job_id, video_path=video, workspace_root=self.reconstruction_jobs_root))
                current = self.repository.get(job_id) or reconstructing
                self.repository.save(transition_training_job(current, TrainingStage.PREPARING_DATASET, 0.35))
                self.preparer.prepare(job_id=job_id, workspace_root=self.reconstruction_jobs_root, archive=True)
            self.training.submit_prepared_dataset(job_id, archive)
        except Exception as error:
            current = self.repository.get(job_id)
            if current is not None and current.stage not in {"failed", "cancelled", "completed"}:
                self.repository.save(transition_training_job(current, TrainingStage.FAILED, current.progress, training_error=str(error)[:500], training_failure_reason="reconstruction_or_submission_failure"))

    def shutdown(self) -> None:
        self.executor.shutdown(wait=False, cancel_futures=True)
