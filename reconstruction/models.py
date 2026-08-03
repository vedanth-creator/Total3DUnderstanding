"""JSON-serializable result models for sparse reconstruction jobs."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class SparseModelSummary:
    model_id: str
    path: str
    registered_image_count: Optional[int] = None
    sparse_point_count: Optional[int] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "model_id": self.model_id,
            "path": self.path,
            "registered_image_count": self.registered_image_count,
            "sparse_point_count": self.sparse_point_count,
        }


@dataclass(frozen=True)
class ReconstructionResult:
    job_id: str
    status: str
    video_path: str
    job_directory: str
    images_directory: str
    database_path: str
    sparse_directory: str
    logs_directory: str
    extracted_frame_count: int
    registered_image_count: int
    sparse_point_count: int
    matcher_used: Optional[str]
    retry_attempted: bool
    retry_succeeded: bool
    reconstruction_duration_seconds: float
    sparse_models: List[SparseModelSummary] = field(default_factory=list)
    error: Optional[str] = None
    failure_reason: Optional[str] = None
    recommendations: List[str] = field(default_factory=list)
    completed_at: str = field(default_factory=utc_now_iso)
    schema_version: str = "1.0"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "job_id": self.job_id,
            "status": self.status,
            "video_path": self.video_path,
            "job_directory": self.job_directory,
            "images_directory": self.images_directory,
            "database_path": self.database_path,
            "sparse_directory": self.sparse_directory,
            "logs_directory": self.logs_directory,
            "extracted_frame_count": self.extracted_frame_count,
            "registered_image_count": self.registered_image_count,
            "sparse_point_count": self.sparse_point_count,
            "matcher_used": self.matcher_used,
            "retry_attempted": self.retry_attempted,
            "retry_succeeded": self.retry_succeeded,
            "reconstruction_duration_seconds": float(
                self.reconstruction_duration_seconds
            ),
            "sparse_models": [model.to_dict() for model in self.sparse_models],
            "error": self.error,
            "failure_reason": self.failure_reason,
            "recommendations": list(self.recommendations),
            "completed_at": self.completed_at,
        }

    def write_json(self, destination: Path) -> None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix(destination.suffix + ".tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(self.to_dict(), handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))
