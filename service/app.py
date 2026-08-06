"""FastAPI application for scene and room-scan milestones.

Scene inference remains CPU-only and uses a fake GPU response. Room-scan
reconstruction selects the remote training pipeline only when its complete
environment is configured, while retaining dependency injection for tests.
"""

from contextlib import asynccontextmanager
import os
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence

from fastapi import Body, FastAPI, HTTPException

from service.artifact_storage import S3CompatibleArtifactStorage
from service.gpu_jobs import RunPodGPUJobProvider
from service.pipeline import (
    DecodedCamera,
    DecodedObject,
    DecodedRoomLayout,
    DecodedScene,
    FakeGPUClient,
    GPUClient,
    NoUsableDetectionsError,
    ScenePipeline,
)
from service.providers import (
    Detection,
    DetectionProvider,
    IntrinsicsProvider,
    ScaledCanonicalIntrinsicsProvider,
    StaticDetectionProvider,
)
from service.job_repository import FileJobRepository
from service.reconstruction import (
    FakeReconstructionProcessor,
    ReconstructionProcessor,
)
from service.remote_reconstruction import RemoteTrainingReconstructionProcessor
from service.room_scan_routes import SceneFactory, create_room_scan_router
from service.sample_scene import make_sample_scene
from service.upload_storage import LocalUploadStorage
from service.training_orchestrator import TrainingOrchestrator


DetectionProviderFactory = Callable[
    [str, Sequence[Detection]], DetectionProvider
]
GPUClientFactory = Callable[[int], GPUClient]


REMOTE_TRAINING_ENVIRONMENT_VARIABLES = (
    "RUNPOD_API_KEY",
    "RUNPOD_ENDPOINT_ID",
    "ARTIFACT_S3_BUCKET",
    "ARTIFACT_S3_ENDPOINT_URL",
    "ARTIFACT_S3_REGION",
    "ARTIFACT_S3_ACCESS_KEY_ID",
    "ARTIFACT_S3_SECRET_ACCESS_KEY",
)


IDENTITY = (
    (1.0, 0.0, 0.0),
    (0.0, 1.0, 0.0),
    (0.0, 0.0, 1.0),
)

CORNERS = (
    (-1.0, 1.0, -1.0),
    (-1.0, 1.0, 1.0),
    (1.0, 1.0, 1.0),
    (1.0, 1.0, -1.0),
    (-1.0, -1.0, -1.0),
    (-1.0, -1.0, 1.0),
    (1.0, -1.0, 1.0),
    (1.0, -1.0, -1.0),
)


def _static_detection_provider_factory(
    image_id: str, detections: Sequence[Detection]
) -> DetectionProvider:
    del image_id
    return StaticDetectionProvider(detections)


def _fake_gpu_client_factory(detection_count: int) -> GPUClient:
    objects = tuple(
        DecodedObject(
            detection_index=index,
            object_id="object-%d" % index,
            corners=CORNERS,
            centroid=(float(index), 0.0, 0.0),
            basis=IDENTITY,
            half_sizes=(1.0, 1.0, 1.0),
            orientation_bin_probability=0.8,
            depth_bin_probability=0.7,
            mesh_uri="meshes/object-%d.obj" % index,
            mesh_coordinate_frame="total3d_scene_frame_unverified",
        )
        for index in range(detection_count)
    )
    return FakeGPUClient(
        DecodedScene(
            coordinate_system_name="total3d_scene_frame_unverified",
            coordinate_system_units="units_unverified",
            camera=DecodedCamera(
                rotation=IDENTITY,
                pitch_radians=0.0,
                roll_radians=0.0,
                pitch_bin_probability=0.8,
                roll_bin_probability=0.8,
            ),
            room_layout=DecodedRoomLayout(
                corners=CORNERS,
                centroid=(0.0, 0.0, 0.0),
                basis=IDENTITY,
                half_sizes=(1.0, 1.0, 1.0),
                orientation_bin_probability=0.8,
            ),
            objects=objects,
            warnings=("Scene geometry was produced by the CPU-only fake GPU client.",),
        )
    )


def _remote_training_is_configured() -> bool:
    return all(
        os.environ.get(variable_name, "").strip()
        for variable_name in REMOTE_TRAINING_ENVIRONMENT_VARIABLES
    )


def _required_positive_integer(payload: Dict[str, Any], field_name: str) -> int:
    value = payload.get(field_name)
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise HTTPException(
            status_code=422,
            detail="%s must be a positive integer." % field_name,
        )
    return value


def _parse_detections(payload: Dict[str, Any]) -> List[Detection]:
    raw_detections = payload.get("detections", [])
    if raw_detections is None:
        raw_detections = []
    if not isinstance(raw_detections, list):
        raise HTTPException(
            status_code=422,
            detail="detections must be a JSON array when provided.",
        )

    detections: List[Detection] = []
    for index, raw_detection in enumerate(raw_detections):
        if not isinstance(raw_detection, dict):
            raise HTTPException(
                status_code=422,
                detail="detection %d must be a JSON object." % index,
            )
        try:
            raw_bbox = raw_detection["bbox_xyxy"]
            if not isinstance(raw_bbox, (list, tuple)) or len(raw_bbox) != 4:
                raise ValueError("bbox_xyxy must contain four values")
            detection = Detection(
                bbox_xyxy=tuple(float(value) for value in raw_bbox),
                category_name=str(raw_detection["category_name"]),
                nyu40_id=int(raw_detection["nyu40_id"]),
                score=float(raw_detection["score"]),
            )
        except (KeyError, TypeError, ValueError) as error:
            raise HTTPException(
                status_code=422,
                detail="Malformed detection %d: %s" % (index, error),
            ) from error
        detections.append(detection)
    return detections


def create_app(
    detection_provider_factory: Optional[DetectionProviderFactory] = None,
    intrinsics_provider: Optional[IntrinsicsProvider] = None,
    gpu_client_factory: Optional[GPUClientFactory] = None,
    storage_root: Optional[Path] = None,
    maximum_upload_bytes: int = 500 * 1024 * 1024,
    job_repository: Optional[FileJobRepository] = None,
    upload_storage: Optional[LocalUploadStorage] = None,
    reconstruction_processor: Optional[ReconstructionProcessor] = None,
    room_scan_scene_factory: Optional[SceneFactory] = None,
    training_orchestrator: Optional[TrainingOrchestrator] = None,
) -> FastAPI:
    """Create the HTTP application with replaceable pipeline dependencies."""

    provider_factory = (
        detection_provider_factory or _static_detection_provider_factory
    )
    camera_provider = intrinsics_provider or ScaledCanonicalIntrinsicsProvider()
    client_factory = gpu_client_factory or _fake_gpu_client_factory
    local_storage_root = (storage_root or Path("storage")).resolve()
    repository = job_repository or FileJobRepository(local_storage_root / "jobs")
    video_storage = upload_storage or LocalUploadStorage(
        local_storage_root,
        maximum_upload_bytes=maximum_upload_bytes,
    )
    effective_training_orchestrator = training_orchestrator
    if reconstruction_processor is not None:
        processor: ReconstructionProcessor = reconstruction_processor
    elif _remote_training_is_configured():
        if effective_training_orchestrator is None:
            artifact_storage = S3CompatibleArtifactStorage.from_environment()
            gpu_job_provider = RunPodGPUJobProvider.from_environment()
            effective_training_orchestrator = TrainingOrchestrator(
                repository,
                artifact_storage,
                gpu_job_provider,
                maximum_iterations=int(
                    os.environ.get("NERFSTUDIO_MAX_ITERATIONS", "30000")
                ),
                stale_after_seconds=int(
                    os.environ.get("GPU_JOB_STALE_SECONDS", "28800")
                ),
            )
        processor = RemoteTrainingReconstructionProcessor(
            repository=repository,
            storage_root=local_storage_root,
            reconstruction_jobs_root=Path("reconstruction/jobs"),
            training=effective_training_orchestrator,
        )
    else:
        processor = FakeReconstructionProcessor(repository)
    scene_factory = room_scan_scene_factory or make_sample_scene

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        del application
        processor.resume_incomplete()
        if effective_training_orchestrator is not None:
            effective_training_orchestrator.reconcile_once()
        yield
        processor.shutdown()

    application = FastAPI(
        title="Total3D CPU-only scene API",
        version="0.2.0",
        lifespan=lifespan,
    )
    application.include_router(
        create_room_scan_router(
            repository=repository,
            upload_storage=video_storage,
            processor=processor,
            scene_factory=scene_factory,
            training_orchestrator=effective_training_orchestrator,
        )
    )
    application.state.reconstruction_processor = processor
    application.state.training_orchestrator = effective_training_orchestrator

    @application.get("/health")
    def health() -> Dict[str, str]:
        return {"status": "ok", "mode": "cpu-only-fake-gpu"}

    @application.post("/v1/scenes/infer")
    def infer_scene(
        payload: Dict[str, Any] = Body(...),
    ) -> Dict[str, Any]:
        image_id = payload.get("image_id")
        if not isinstance(image_id, str) or not image_id.strip():
            raise HTTPException(
                status_code=422,
                detail="image_id must be a non-empty string.",
            )
        image_width = _required_positive_integer(payload, "image_width")
        image_height = _required_positive_integer(payload, "image_height")
        detections = _parse_detections(payload)

        pipeline = ScenePipeline(
            detection_provider=provider_factory(image_id, detections),
            intrinsics_provider=camera_provider,
            gpu_client=client_factory(len(detections)),
        )
        try:
            scene = pipeline.run(
                image_width=image_width,
                image_height=image_height,
                image_reference=image_id,
            )
        except NoUsableDetectionsError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error

        return scene.to_dict()

    return application


app = create_app()
