"""Durable GPU training submission, reconciliation, and cancellation."""

from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional
from uuid import uuid4

from service.api_schemas import RoomScanJob, utc_now_iso
from service.artifact_storage import ArtifactStorage
from service.gpu_jobs import GPUJobProvider, GPUJobState
from service.job_repository import FileJobRepository
from service.training_state import TrainingStage, transition_training_job


class TrainingSubmissionError(RuntimeError):
    pass


class TrainingOrchestrator:
    def __init__(self, repository: FileJobRepository, storage: ArtifactStorage, provider: GPUJobProvider, maximum_iterations: int = 30000, stale_after_seconds: int = 8 * 60 * 60) -> None:
        self.repository = repository
        self.storage = storage
        self.provider = provider
        self.maximum_iterations = maximum_iterations
        self.stale_after_seconds = stale_after_seconds

    @staticmethod
    def artifact_keys(job_id: str) -> Dict[str, str]:
        root = "room-scans/%s" % job_id
        return {
            "dataset": root + "/inputs/nerfstudio-data.tar.gz",
            "splat": root + "/outputs/splat.ply",
            "training_archive": root + "/outputs/nerfstudio-training.tar.gz",
            "log": root + "/logs/training.log",
            "result_manifest": root + "/outputs/result.json",
        }

    def submit_prepared_dataset(self, job_id: str, dataset_archive: Path, startup_test: bool = True) -> RoomScanJob:
        job = self._require_job(job_id)
        if job.provider_job_id:
            return job
        keys = self.artifact_keys(job_id)
        self.storage.upload_file(dataset_archive, keys["dataset"])
        correlation_id = job.correlation_id or str(uuid4())
        payload = {
            "schema_version": "1.0",
            "room_scan_id": job_id,
            "dataset_download_url": self.storage.create_download_url(keys["dataset"]),
            "dataset_object_key": keys["dataset"],
            "artifact_upload_urls": {name: self.storage.create_upload_url(key) for name, key in keys.items() if name != "dataset"},
            "artifact_object_keys": {name: key for name, key in keys.items() if name != "dataset"},
            "requested_method": "splatfacto",
            "maximum_iterations": self.maximum_iterations,
            "viewer_configuration": {"enabled": False},
            "startup_test": startup_test,
            "correlation_id": correlation_id,
        }
        provider_job_id = self.provider.submit_training_job(payload)
        updated = transition_training_job(job, TrainingStage.QUEUED_FOR_GPU, 0.45, provider_job_id=provider_job_id, submitted_at=utc_now_iso(), dataset_object_key=keys["dataset"], correlation_id=correlation_id)
        return self.repository.save(updated)

    def reconcile_once(self) -> None:
        for job in self.repository.list_jobs():
            if not job.provider_job_id or job.stage in {"completed", "failed", "cancelled"}:
                continue
            if self._is_stale(job):
                failed = transition_training_job(job, TrainingStage.FAILED, job.progress, training_error="GPU job exceeded the configured stale-job limit.", training_failure_reason="infrastructure_failure")
                self.repository.save(failed)
                continue
            try:
                self._reconcile_job(job)
            except Exception as error:
                self.repository.save(replace(job, training_error=str(error)[:500]))

    def _reconcile_job(self, job: RoomScanJob) -> RoomScanJob:
        remote = self.provider.get_training_job(job.provider_job_id or "")
        if remote.state == GPUJobState.QUEUED:
            return job
        if remote.state == GPUJobState.RUNNING:
            stage = TrainingStage(remote.stage) if remote.stage in {value.value for value in TrainingStage} else TrainingStage.TRAINING
            changes = {}
            if not job.training_started_at:
                changes["training_started_at"] = utc_now_iso()
            return self.repository.save(transition_training_job(job, stage, remote.progress or max(job.progress, 0.5), **changes))
        if remote.state == GPUJobState.CANCELLED:
            return self.repository.save(transition_training_job(job, TrainingStage.CANCELLED, job.progress))
        if remote.state == GPUJobState.FAILED or not remote.output or remote.output.get("status") != "completed":
            output = remote.output or {}
            keys = self.artifact_keys(job.job_id)
            log_key = keys["log"] if self.storage.object_exists(keys["log"]) else None
            manifest_key = keys["result_manifest"] if self.storage.object_exists(keys["result_manifest"]) else None
            return self.repository.save(transition_training_job(job, TrainingStage.FAILED, job.progress, training_completed_at=utc_now_iso(), training_log_object_key=log_key, result_manifest_object_key=manifest_key, training_error=str(output.get("error") or remote.error or "GPU job failed")[:500], training_failure_reason=str(output.get("failure_reason") or "training_failure")))
        keys = self.artifact_keys(job.job_id)
        required = ("splat", "training_archive", "log", "result_manifest")
        if not all(self.storage.object_exists(keys[name]) for name in required):
            return self.repository.save(transition_training_job(job, TrainingStage.UPLOADING_ARTIFACTS, 0.98, training_error="Waiting for required artifacts."))
        completed_at = utc_now_iso()
        duration = remote.output.get("duration_seconds")
        completed = transition_training_job(job, TrainingStage.COMPLETED, 1.0, training_started_at=job.training_started_at or job.submitted_at, training_completed_at=completed_at, training_duration_seconds=float(duration) if duration is not None else None, splat_object_key=keys["splat"], training_archive_object_key=keys["training_archive"], training_log_object_key=keys["log"], result_manifest_object_key=keys["result_manifest"])
        return self.repository.save(completed)

    def cancel(self, job_id: str) -> RoomScanJob:
        job = self._require_job(job_id)
        if job.stage in {"completed", "failed", "cancelled"}:
            return job
        if job.provider_job_id:
            self.provider.cancel_training_job(job.provider_job_id)
        return self.repository.save(transition_training_job(job, TrainingStage.CANCELLED, job.progress))

    def artifact_url(self, job_id: str, kind: str) -> str:
        job = self._require_job(job_id)
        key = {"splat": job.splat_object_key, "training_archive": job.training_archive_object_key, "logs": job.training_log_object_key}.get(kind)
        if not key or not self.storage.object_exists(key):
            raise KeyError(kind)
        return self.storage.create_download_url(key)

    def _require_job(self, job_id: str) -> RoomScanJob:
        job = self.repository.get(job_id)
        if job is None:
            raise KeyError(job_id)
        return job

    def _is_stale(self, job: RoomScanJob) -> bool:
        if not job.submitted_at:
            return False
        try:
            submitted = datetime.fromisoformat(job.submitted_at)
        except ValueError:
            return True
        if submitted.tzinfo is None:
            submitted = submitted.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - submitted).total_seconds() > self.stale_after_seconds
