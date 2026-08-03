"""Validated, idempotent room-scan training state transitions."""

from dataclasses import replace
from enum import Enum
from typing import Any

from service.api_schemas import JobStatus, RoomScanJob, utc_now_iso


class TrainingStage(str, Enum):
    UPLOADED = "uploaded"
    RECONSTRUCTING = "reconstructing"
    PREPARING_DATASET = "preparing_dataset"
    QUEUED_FOR_GPU = "queued_for_gpu"
    TRAINING = "training"
    EXPORTING = "exporting"
    UPLOADING_ARTIFACTS = "uploading_artifacts"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


_ORDER = {
    TrainingStage.UPLOADED: 0,
    TrainingStage.RECONSTRUCTING: 1,
    TrainingStage.PREPARING_DATASET: 2,
    TrainingStage.QUEUED_FOR_GPU: 3,
    TrainingStage.TRAINING: 4,
    TrainingStage.EXPORTING: 5,
    TrainingStage.UPLOADING_ARTIFACTS: 6,
    TrainingStage.COMPLETED: 7,
}
_TERMINAL = {TrainingStage.COMPLETED, TrainingStage.FAILED, TrainingStage.CANCELLED}


class InvalidTrainingTransition(ValueError):
    pass


def transition_training_job(
    job: RoomScanJob,
    target: TrainingStage,
    progress: float,
    **changes: Any,
) -> RoomScanJob:
    try:
        current = TrainingStage(job.stage)
    except ValueError:
        current = TrainingStage.UPLOADED
    if current == target:
        return replace(
            job,
            progress=max(job.progress, min(max(float(progress), 0.0), 1.0)),
            updated_at=utc_now_iso(),
            **changes,
        )
    if current in _TERMINAL:
        raise InvalidTrainingTransition("Cannot transition terminal stage %s." % current.value)
    if target not in _TERMINAL and _ORDER[target] < _ORDER.get(current, 0):
        raise InvalidTrainingTransition(
            "Cannot move training backward from %s to %s."
            % (current.value, target.value)
        )
    status = JobStatus.PROCESSING
    if target == TrainingStage.QUEUED_FOR_GPU:
        status = JobStatus.QUEUED
    elif target == TrainingStage.COMPLETED:
        status = JobStatus.COMPLETED
    elif target == TrainingStage.FAILED:
        status = JobStatus.FAILED
    elif target == TrainingStage.CANCELLED:
        status = JobStatus.CANCELLED
    return replace(
        job,
        status=status,
        stage=target.value,
        progress=min(max(float(progress), 0.0), 1.0),
        updated_at=utc_now_iso(),
        **changes,
    )
