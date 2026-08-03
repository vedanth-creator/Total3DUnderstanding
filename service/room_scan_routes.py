"""FastAPI routes for local room-video upload and fake reconstruction jobs."""

import json
from typing import Any, Callable, Dict, Optional
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status
from fastapi.responses import RedirectResponse

from service.api_schemas import (
    ClientScanMetadata,
    JobStatus,
    RoomScanAccepted,
    RoomScanJob,
)
from service.contracts import SceneResult
from service.job_repository import FileJobRepository, InvalidJobIDError
from service.reconstruction import FakeReconstructionProcessor
from service.upload_storage import (
    LocalUploadStorage,
    UploadTooLargeError,
    UploadValidationError,
)
from service.training_orchestrator import TrainingOrchestrator


SceneFactory = Callable[[RoomScanJob], SceneResult]


def _parse_client_metadata(
    client_metadata: Optional[str],
    duration_seconds: Optional[float],
    width: Optional[int],
    height: Optional[int],
    source: Optional[str],
    client_scan_id: Optional[str],
) -> ClientScanMetadata:
    payload: Dict[str, Any] = {}
    if client_metadata:
        try:
            parsed = json.loads(client_metadata)
        except json.JSONDecodeError as error:
            raise HTTPException(422, "client_metadata must be valid JSON.") from error
        if not isinstance(parsed, dict):
            raise HTTPException(422, "client_metadata must be a JSON object.")
        payload.update(parsed)

    explicit = {
        "duration_seconds": duration_seconds,
        "width": width,
        "height": height,
        "source": source,
        "client_scan_id": client_scan_id,
    }
    payload.update({key: value for key, value in explicit.items() if value is not None})

    duration = payload.get("duration_seconds")
    if duration is not None:
        try:
            duration = float(duration)
        except (TypeError, ValueError) as error:
            raise HTTPException(422, "duration_seconds must be numeric.") from error
        if duration < 0:
            raise HTTPException(422, "duration_seconds must not be negative.")

    parsed_dimensions: Dict[str, Optional[int]] = {}
    for key in ("width", "height"):
        value = payload.get(key)
        if value is None:
            parsed_dimensions[key] = None
            continue
        if isinstance(value, bool):
            raise HTTPException(422, "%s must be a positive integer." % key)
        try:
            integer = int(value)
        except (TypeError, ValueError) as error:
            raise HTTPException(422, "%s must be a positive integer." % key) from error
        if integer <= 0:
            raise HTTPException(422, "%s must be a positive integer." % key)
        parsed_dimensions[key] = integer

    return ClientScanMetadata(
        duration_seconds=duration,
        width=parsed_dimensions["width"],
        height=parsed_dimensions["height"],
        source=str(payload["source"]) if payload.get("source") is not None else None,
        client_scan_id=(
            str(payload["client_scan_id"])
            if payload.get("client_scan_id") is not None
            else None
        ),
    )


def create_room_scan_router(
    repository: FileJobRepository,
    upload_storage: LocalUploadStorage,
    processor: FakeReconstructionProcessor,
    scene_factory: SceneFactory,
    training_orchestrator: Optional[TrainingOrchestrator] = None,
) -> APIRouter:
    router = APIRouter(prefix="/v1/room-scans", tags=["room-scans"])

    @router.post("", status_code=status.HTTP_202_ACCEPTED)
    async def create_room_scan(
        video: UploadFile = File(...),
        client_metadata: Optional[str] = Form(None),
        duration_seconds: Optional[float] = Form(None),
        width: Optional[int] = Form(None),
        height: Optional[int] = Form(None),
        source: Optional[str] = Form(None),
        client_scan_id: Optional[str] = Form(None),
    ) -> Dict[str, Any]:
        metadata = _parse_client_metadata(
            client_metadata,
            duration_seconds,
            width,
            height,
            source,
            client_scan_id,
        )
        job_id = str(uuid4())
        try:
            stored = await upload_storage.save(job_id, video)
        except UploadTooLargeError as error:
            raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, str(error)) from error
        except UploadValidationError as error:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(error)) from error

        try:
            job = repository.create(
                job_id=job_id,
                upload_relative_path=stored.relative_path,
                upload_size_bytes=stored.size_bytes,
                client_metadata=metadata,
            )
        except Exception:
            upload_storage.delete_job_upload(job_id)
            raise

        processor.submit(job_id)
        return RoomScanAccepted(
            job_id=job.job_id,
            status=job.status,
            created_at=job.created_at,
        ).to_dict()

    @router.get("/{job_id}")
    def get_room_scan(job_id: str) -> Dict[str, Any]:
        try:
            job = repository.get(job_id)
        except InvalidJobIDError as error:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Room-scan job not found.") from error
        if job is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Room-scan job not found.")
        return job.to_dict()

    @router.get("/{job_id}/scene")
    def get_room_scan_scene(job_id: str) -> Dict[str, Any]:
        try:
            job = repository.get(job_id)
        except InvalidJobIDError as error:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Room-scan job not found.") from error
        if job is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Room-scan job not found.")
        if job.status != JobStatus.COMPLETED:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Room-scan scene is not available until the job completes.",
            )
        return scene_factory(job).to_dict()

    @router.post("/{job_id}/cancel")
    def cancel_training(job_id: str) -> Dict[str, Any]:
        if training_orchestrator is None:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Remote training is not configured.")
        try:
            return training_orchestrator.cancel(job_id).to_dict()
        except (KeyError, InvalidJobIDError) as error:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Room-scan job not found.") from error

    @router.get("/{job_id}/artifacts/{artifact_kind}")
    def download_artifact(job_id: str, artifact_kind: str) -> RedirectResponse:
        if training_orchestrator is None:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Remote training is not configured.")
        if artifact_kind not in {"splat", "training_archive", "logs"}:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Artifact not found.")
        try:
            url = training_orchestrator.artifact_url(job_id, artifact_kind)
        except (KeyError, InvalidJobIDError) as error:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Artifact not found.") from error
        return RedirectResponse(url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)

    return router
