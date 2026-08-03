"""Thread-safe JSON persistence for local room-scan jobs."""

import json
import os
from pathlib import Path
import threading
from typing import List, Optional
from uuid import UUID

from service.api_schemas import (
    ClientScanMetadata,
    JobStatus,
    RoomScanJob,
    utc_now_iso,
)


class InvalidJobIDError(ValueError):
    pass


def canonical_job_id(job_id: str) -> str:
    try:
        parsed = UUID(job_id)
    except (ValueError, TypeError, AttributeError) as error:
        raise InvalidJobIDError("Invalid room-scan job ID.") from error
    canonical = str(parsed)
    if canonical != job_id.lower():
        raise InvalidJobIDError("Invalid room-scan job ID.")
    return canonical


class FileJobRepository:
    def __init__(self, jobs_directory: Path) -> None:
        self.jobs_directory = jobs_directory.resolve()
        self.jobs_directory.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def create(
        self,
        job_id: str,
        upload_relative_path: str,
        upload_size_bytes: int,
        client_metadata: ClientScanMetadata,
    ) -> RoomScanJob:
        canonical_job_id(job_id)
        now = utc_now_iso()
        job = RoomScanJob(
            job_id=job_id,
            status=JobStatus.QUEUED,
            progress=0.0,
            stage="queued",
            error=None,
            created_at=now,
            updated_at=now,
            upload_relative_path=upload_relative_path,
            upload_size_bytes=upload_size_bytes,
            client_metadata=client_metadata,
        )
        with self._lock:
            self._write(job)
        return job

    def get(self, job_id: str) -> Optional[RoomScanJob]:
        path = self._path_for(job_id)
        with self._lock:
            if not path.is_file():
                return None
            with path.open("r", encoding="utf-8") as handle:
                return RoomScanJob.from_dict(json.load(handle))

    def update(
        self,
        job_id: str,
        status: JobStatus,
        progress: float,
        stage: str,
        error: Optional[str] = None,
    ) -> RoomScanJob:
        with self._lock:
            existing = self.get(job_id)
            if existing is None:
                raise KeyError(job_id)
            updated = RoomScanJob(
                job_id=existing.job_id,
                status=status,
                progress=min(max(float(progress), 0.0), 1.0),
                stage=stage,
                error=error,
                created_at=existing.created_at,
                updated_at=utc_now_iso(),
                upload_relative_path=existing.upload_relative_path,
                upload_size_bytes=existing.upload_size_bytes,
                client_metadata=existing.client_metadata,
            )
            self._write(updated)
            return updated

    def list_jobs(self) -> List[RoomScanJob]:
        jobs: List[RoomScanJob] = []
        with self._lock:
            for path in sorted(self.jobs_directory.glob("*.json")):
                try:
                    with path.open("r", encoding="utf-8") as handle:
                        jobs.append(RoomScanJob.from_dict(json.load(handle)))
                except (KeyError, TypeError, ValueError, json.JSONDecodeError):
                    continue
        return jobs

    def delete(self, job_id: str) -> None:
        path = self._path_for(job_id)
        with self._lock:
            if path.exists():
                path.unlink()

    def _path_for(self, job_id: str) -> Path:
        canonical = canonical_job_id(job_id)
        path = (self.jobs_directory / (canonical + ".json")).resolve()
        if path.parent != self.jobs_directory:
            raise InvalidJobIDError("Invalid room-scan job path.")
        return path

    def _write(self, job: RoomScanJob) -> None:
        destination = self._path_for(job.job_id)
        temporary = destination.with_suffix(".json.tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(job.to_dict(include_internal=True), handle, indent=2, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))
