"""JSON-neutral schemas for persistent room-scan jobs."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, Optional


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class JobStatus(str, Enum):
    QUEUED = "queued"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass(frozen=True)
class ClientScanMetadata:
    duration_seconds: Optional[float] = None
    width: Optional[int] = None
    height: Optional[int] = None
    source: Optional[str] = None
    client_scan_id: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "duration_seconds": self.duration_seconds,
            "width": self.width,
            "height": self.height,
            "source": self.source,
            "client_scan_id": self.client_scan_id,
        }

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "ClientScanMetadata":
        return cls(
            duration_seconds=payload.get("duration_seconds"),
            width=payload.get("width"),
            height=payload.get("height"),
            source=payload.get("source"),
            client_scan_id=payload.get("client_scan_id"),
        )


@dataclass(frozen=True)
class RoomScanJob:
    job_id: str
    status: JobStatus
    progress: float
    stage: str
    created_at: str
    updated_at: str
    upload_relative_path: str
    upload_size_bytes: int
    client_metadata: ClientScanMetadata = field(default_factory=ClientScanMetadata)
    error: Optional[str] = None
    provider_job_id: Optional[str] = None
    submitted_at: Optional[str] = None
    training_started_at: Optional[str] = None
    training_completed_at: Optional[str] = None
    training_duration_seconds: Optional[float] = None
    dataset_object_key: Optional[str] = None
    splat_object_key: Optional[str] = None
    training_archive_object_key: Optional[str] = None
    training_log_object_key: Optional[str] = None
    result_manifest_object_key: Optional[str] = None
    training_error: Optional[str] = None
    training_failure_reason: Optional[str] = None
    correlation_id: Optional[str] = None

    def to_dict(self, include_internal: bool = False) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "job_id": self.job_id,
            "status": self.status.value,
            "progress": float(self.progress),
            "stage": self.stage,
            "error": self.error,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "client_metadata": self.client_metadata.to_dict(),
            "training": {
                "stage": self.stage,
                "progress": float(self.progress),
                "submitted_at": self.submitted_at,
                "started_at": self.training_started_at,
                "completed_at": self.training_completed_at,
                "duration_seconds": self.training_duration_seconds,
                "artifact_availability": {
                    "splat": self.splat_object_key is not None,
                    "training_archive": self.training_archive_object_key is not None,
                    "logs": self.training_log_object_key is not None,
                },
                "viewer_ready": (
                    self.status == JobStatus.COMPLETED
                    and self.splat_object_key is not None
                ),
                "failure_reason": self.training_failure_reason,
                "error": self.training_error,
            },
        }
        if include_internal:
            payload.update(
                {
                    "upload_relative_path": self.upload_relative_path,
                    "upload_size_bytes": self.upload_size_bytes,
                    "provider_job_id": self.provider_job_id,
                    "dataset_object_key": self.dataset_object_key,
                    "splat_object_key": self.splat_object_key,
                    "training_archive_object_key": self.training_archive_object_key,
                    "training_log_object_key": self.training_log_object_key,
                    "result_manifest_object_key": self.result_manifest_object_key,
                    "correlation_id": self.correlation_id,
                }
            )
        return payload

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "RoomScanJob":
        return cls(
            job_id=str(payload["job_id"]),
            status=JobStatus(str(payload["status"])),
            progress=float(payload["progress"]),
            stage=str(payload["stage"]),
            error=payload.get("error"),
            created_at=str(payload["created_at"]),
            updated_at=str(payload["updated_at"]),
            upload_relative_path=str(payload["upload_relative_path"]),
            upload_size_bytes=int(payload["upload_size_bytes"]),
            client_metadata=ClientScanMetadata.from_dict(
                dict(payload.get("client_metadata") or {})
            ),
            provider_job_id=payload.get("provider_job_id"),
            submitted_at=payload.get("submitted_at"),
            training_started_at=payload.get("training_started_at"),
            training_completed_at=payload.get("training_completed_at"),
            training_duration_seconds=payload.get("training_duration_seconds"),
            dataset_object_key=payload.get("dataset_object_key"),
            splat_object_key=payload.get("splat_object_key"),
            training_archive_object_key=payload.get("training_archive_object_key"),
            training_log_object_key=payload.get("training_log_object_key"),
            result_manifest_object_key=payload.get("result_manifest_object_key"),
            training_error=payload.get("training_error"),
            training_failure_reason=payload.get("training_failure_reason"),
            correlation_id=payload.get("correlation_id"),
        )


@dataclass(frozen=True)
class RoomScanAccepted:
    job_id: str
    status: JobStatus
    created_at: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "job_id": self.job_id,
            "status": self.status.value,
            "created_at": self.created_at,
            "status_url": "/v1/room-scans/%s" % self.job_id,
        }
