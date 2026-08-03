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
        }
        if include_internal:
            payload.update(
                {
                    "upload_relative_path": self.upload_relative_path,
                    "upload_size_bytes": self.upload_size_bytes,
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
