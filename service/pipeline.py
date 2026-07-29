"""CPU-only orchestration between input providers and a future GPU worker.

This module defines transport structures for decoded Total3D output, but it
does not import or execute any legacy model code. A production ``GPUClient``
can later translate these structures across a process or service boundary.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
import time
from typing import Any, Dict, List, Optional, Sequence, Tuple

from service.contracts import (
    BoundingBox2D,
    BoundingBox3D,
    CameraConfidence,
    CameraData,
    CoordinateSystem,
    DetectedObject,
    ImageInfo,
    LayoutConfidence,
    MeshReference,
    ObjectCategory,
    ObjectConfidence,
    RoomLayout,
    SceneResult,
    TimingInfo,
)
from service.providers import (
    Detection,
    DetectionProvider,
    IntrinsicsProvider,
    IntrinsicsResult,
    SUPPORTED_MESH_CATEGORIES,
)


Vector = Sequence[float]
Matrix = Sequence[Sequence[float]]


def _vector(value: Vector) -> List[float]:
    return [float(component) for component in value]


def _matrix(value: Matrix) -> List[List[float]]:
    return [_vector(row) for row in value]


class PipelineError(Exception):
    """Base exception for scene-pipeline domain errors."""


class NoUsableDetectionsError(PipelineError):
    """Raised when a detector supplies no objects usable by Total3D."""


class InvalidGPUResponseError(PipelineError):
    """Raised when decoded GPU data cannot be matched to the request."""


@dataclass(frozen=True)
class GPURequest:
    """Normalized request sent to a future legacy Total3D worker."""

    image_reference: str
    image_width: int
    image_height: int
    camera_intrinsics: Matrix
    detections: Tuple[Detection, ...]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "image_reference": self.image_reference,
            "image_width": self.image_width,
            "image_height": self.image_height,
            "camera_intrinsics": _matrix(self.camera_intrinsics),
            "detections": [detection.to_dict() for detection in self.detections],
        }


@dataclass(frozen=True)
class DecodedCamera:
    """Decoded camera output from the model worker."""

    rotation: Matrix
    pitch_radians: float
    roll_radians: float
    pitch_bin_probability: Optional[float] = None
    roll_bin_probability: Optional[float] = None


@dataclass(frozen=True)
class DecodedRoomLayout:
    """Decoded room-layout output from the model worker."""

    corners: Matrix
    centroid: Vector
    basis: Matrix
    half_sizes: Vector
    orientation_bin_probability: Optional[float] = None


@dataclass(frozen=True)
class DecodedObject:
    """Decoded 3D output associated with one requested detection."""

    detection_index: int
    object_id: str
    corners: Matrix
    centroid: Vector
    basis: Matrix
    half_sizes: Vector
    orientation_bin_probability: Optional[float]
    depth_bin_probability: Optional[float]
    mesh_uri: str
    mesh_media_type: str = "model/obj"
    mesh_coordinate_frame: Optional[str] = None


@dataclass(frozen=True)
class DecodedScene:
    """Decoded, JSON-neutral output returned by a legacy Total3D worker."""

    coordinate_system_name: str
    coordinate_system_units: str
    camera: DecodedCamera
    room_layout: DecodedRoomLayout
    objects: Tuple[DecodedObject, ...]
    coordinate_system_handedness: Optional[str] = None
    coordinate_system_axis_convention: Optional[str] = None
    total3d_ms: Optional[float] = None
    warnings: Tuple[str, ...] = field(default_factory=tuple)


class GPUClient(ABC):
    """Interface to a future process running legacy Total3D inference."""

    @abstractmethod
    def infer(self, request: GPURequest) -> DecodedScene:
        """Run inference and return decoded model data."""


class FakeGPUClient(GPUClient):
    """CPU-only GPU client that returns a predefined decoded response."""

    def __init__(self, response: DecodedScene) -> None:
        self._response = response
        self.last_request: Optional[GPURequest] = None

    def infer(self, request: GPURequest) -> DecodedScene:
        self.last_request = request
        return self._response


class ScenePipeline:
    """Build a normalized scene from providers and decoded model output."""

    def __init__(
        self,
        detection_provider: DetectionProvider,
        intrinsics_provider: IntrinsicsProvider,
        gpu_client: GPUClient,
    ) -> None:
        self._detection_provider = detection_provider
        self._intrinsics_provider = intrinsics_provider
        self._gpu_client = gpu_client

    def run(
        self,
        image_width: int,
        image_height: int,
        image_reference: str = "image-not-yet-attached",
    ) -> SceneResult:
        """Run provider orchestration and normalize the decoded scene."""

        started_at = time.perf_counter()
        detection_started_at = time.perf_counter()
        detections = self._detection_provider.get_detections(
            image_width, image_height
        )
        detection_ms = (time.perf_counter() - detection_started_at) * 1000.0

        if not detections:
            raise NoUsableDetectionsError(
                "No usable Total3D mesh detections remain for this image."
            )

        intrinsics = self._intrinsics_provider.get_intrinsics(
            image_width, image_height
        )
        request = GPURequest(
            image_reference=image_reference,
            image_width=image_width,
            image_height=image_height,
            camera_intrinsics=intrinsics.matrix,
            detections=tuple(detections),
        )
        decoded = self._gpu_client.infer(request)
        scene = self._normalize_scene(
            image_width=image_width,
            image_height=image_height,
            detections=detections,
            intrinsics=intrinsics,
            decoded=decoded,
            detection_ms=detection_ms,
            total_ms=(time.perf_counter() - started_at) * 1000.0,
        )
        return scene

    @staticmethod
    def _normalize_scene(
        image_width: int,
        image_height: int,
        detections: Sequence[Detection],
        intrinsics: IntrinsicsResult,
        decoded: DecodedScene,
        detection_ms: float,
        total_ms: float,
    ) -> SceneResult:
        objects: List[DetectedObject] = []
        seen_detection_indexes = set()

        for model_object in decoded.objects:
            detection_index = model_object.detection_index
            if detection_index < 0 or detection_index >= len(detections):
                raise InvalidGPUResponseError(
                    "GPU object %s references invalid detection index %d."
                    % (model_object.object_id, detection_index)
                )
            if detection_index in seen_detection_indexes:
                raise InvalidGPUResponseError(
                    "GPU response contains duplicate detection index %d."
                    % detection_index
                )
            seen_detection_indexes.add(detection_index)

            detection = detections[detection_index]
            category = SUPPORTED_MESH_CATEGORIES[detection.category_name]
            objects.append(
                DetectedObject(
                    object_id=model_object.object_id,
                    category=ObjectCategory(
                        name=detection.category_name,
                        nyu40_id=detection.nyu40_id,
                        pix3d_id=category.pix3d_id,
                    ),
                    confidence=ObjectConfidence(
                        detector_category_probability=detection.score,
                        orientation_bin_probability=(
                            model_object.orientation_bin_probability
                        ),
                        depth_bin_probability=model_object.depth_bin_probability,
                    ),
                    bounding_box_2d=BoundingBox2D(
                        xyxy=_vector(detection.bbox_xyxy)
                    ),
                    bounding_box_3d=BoundingBox3D(
                        corners=_matrix(model_object.corners),
                        centroid=_vector(model_object.centroid),
                        basis=_matrix(model_object.basis),
                        half_sizes=_vector(model_object.half_sizes),
                    ),
                    mesh=MeshReference(
                        uri=model_object.mesh_uri,
                        media_type=model_object.mesh_media_type,
                        coordinate_frame=model_object.mesh_coordinate_frame,
                    ),
                )
            )

        warnings = list(decoded.warnings)
        if intrinsics.metadata.assumed:
            warnings.append(
                "Camera intrinsics are assumed from scaled canonical demo "
                "intrinsics and are not calibrated for this image."
            )

        return SceneResult(
            image=ImageInfo(width=image_width, height=image_height),
            coordinate_system=CoordinateSystem(
                name=decoded.coordinate_system_name,
                units=decoded.coordinate_system_units,
                handedness=decoded.coordinate_system_handedness,
                axis_convention=decoded.coordinate_system_axis_convention,
            ),
            camera=CameraData(
                intrinsics=_matrix(intrinsics.matrix),
                rotation=_matrix(decoded.camera.rotation),
                pitch_radians=decoded.camera.pitch_radians,
                roll_radians=decoded.camera.roll_radians,
                confidence=CameraConfidence(
                    pitch_bin_probability=(
                        decoded.camera.pitch_bin_probability
                    ),
                    roll_bin_probability=decoded.camera.roll_bin_probability,
                ),
            ),
            room_layout=RoomLayout(
                corners=_matrix(decoded.room_layout.corners),
                centroid=_vector(decoded.room_layout.centroid),
                basis=_matrix(decoded.room_layout.basis),
                half_sizes=_vector(decoded.room_layout.half_sizes),
                confidence=LayoutConfidence(
                    orientation_bin_probability=(
                        decoded.room_layout.orientation_bin_probability
                    )
                ),
            ),
            objects=objects,
            timing=TimingInfo(
                detection_ms=detection_ms,
                total3d_ms=decoded.total3d_ms,
                total_ms=total_ms,
            ),
            warnings=warnings,
        )

