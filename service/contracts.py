"""Standard-library data contracts for normalized Total3D scene results.

Coordinate-system metadata in this module is descriptive and supplied by the
producer of a scene result.  The contracts intentionally do not prescribe a
handedness, axis orientation, world origin, or physical unit because those
details have not yet been verified for every stage of the repository's
inference and mesh-output pipeline.
"""

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


Vector = List[float]
Matrix = List[List[float]]


def _vector_to_list(value: Vector) -> Vector:
    return [float(component) for component in value]


def _matrix_to_lists(value: Matrix) -> Matrix:
    return [_vector_to_list(row) for row in value]


@dataclass
class ImageInfo:
    """Dimensions of the source image in pixels."""

    width: int
    height: int

    def to_dict(self) -> Dict[str, Any]:
        return {"width": self.width, "height": self.height}


@dataclass
class CoordinateSystem:
    """Producer-supplied coordinate-frame metadata.

    ``name`` identifies the frame and ``units`` records the unit label chosen
    by the producer. Optional convention strings should remain unset until the
    corresponding repository behavior has been verified.
    """

    name: str
    units: str
    handedness: Optional[str] = None
    axis_convention: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "units": self.units,
            "handedness": self.handedness,
            "axis_convention": self.axis_convention,
        }


@dataclass
class CameraConfidence:
    """Separate, uncalibrated probabilities for camera angle bins."""

    pitch_bin_probability: Optional[float] = None
    roll_bin_probability: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "pitch_bin_probability": self.pitch_bin_probability,
            "roll_bin_probability": self.roll_bin_probability,
        }


@dataclass
class CameraData:
    """Camera calibration, rotation, and predicted pitch and roll."""

    intrinsics: Matrix
    rotation: Matrix
    pitch_radians: float
    roll_radians: float
    confidence: CameraConfidence = field(default_factory=CameraConfidence)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "intrinsics": _matrix_to_lists(self.intrinsics),
            "rotation": _matrix_to_lists(self.rotation),
            "pitch_radians": float(self.pitch_radians),
            "roll_radians": float(self.roll_radians),
            "confidence": self.confidence.to_dict(),
        }


@dataclass
class LayoutConfidence:
    """Uncalibrated probability for the selected layout orientation bin."""

    orientation_bin_probability: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "orientation_bin_probability": self.orientation_bin_probability,
        }


@dataclass
class RoomLayout:
    """Normalized geometric representation of the estimated room layout."""

    corners: Matrix
    centroid: Vector
    basis: Matrix
    half_sizes: Vector
    confidence: LayoutConfidence = field(default_factory=LayoutConfidence)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "corners": _matrix_to_lists(self.corners),
            "centroid": _vector_to_list(self.centroid),
            "basis": _matrix_to_lists(self.basis),
            "half_sizes": _vector_to_list(self.half_sizes),
            "confidence": self.confidence.to_dict(),
        }


@dataclass
class ObjectCategory:
    """Detector-provided category and optional repository class identifiers."""

    name: str
    nyu40_id: Optional[int] = None
    pix3d_id: Optional[int] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "nyu40_id": self.nyu40_id,
            "pix3d_id": self.pix3d_id,
        }


@dataclass
class ObjectConfidence:
    """Detector and model probabilities kept as distinct values.

    No aggregate 3D confidence is represented because the component
    probabilities have different meanings and have not been calibrated into a
    single score.
    """

    detector_category_probability: float
    orientation_bin_probability: Optional[float] = None
    depth_bin_probability: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "detector_category_probability": float(
                self.detector_category_probability
            ),
            "orientation_bin_probability": self.orientation_bin_probability,
            "depth_bin_probability": self.depth_bin_probability,
        }


@dataclass
class BoundingBox2D:
    """Image-space bounding box in ``[x_min, y_min, x_max, y_max]`` order."""

    xyxy: Vector

    def to_dict(self) -> Dict[str, Any]:
        return {"xyxy": _vector_to_list(self.xyxy)}


@dataclass
class BoundingBox3D:
    """Oriented 3D box geometry in the scene's declared coordinate frame."""

    corners: Matrix
    centroid: Vector
    basis: Matrix
    half_sizes: Vector

    def to_dict(self) -> Dict[str, Any]:
        return {
            "corners": _matrix_to_lists(self.corners),
            "centroid": _vector_to_list(self.centroid),
            "basis": _matrix_to_lists(self.basis),
            "half_sizes": _vector_to_list(self.half_sizes),
        }


@dataclass
class MeshReference:
    """Reference to a mesh artifact and its producer-declared frame."""

    uri: str
    media_type: str = "model/obj"
    coordinate_frame: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "uri": self.uri,
            "media_type": self.media_type,
            "coordinate_frame": self.coordinate_frame,
        }


@dataclass
class DetectedObject:
    """One detected object and its normalized geometry and mesh reference."""

    object_id: str
    category: ObjectCategory
    confidence: ObjectConfidence
    bounding_box_2d: BoundingBox2D
    bounding_box_3d: BoundingBox3D
    mesh: MeshReference

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.object_id,
            "category": self.category.to_dict(),
            "confidence": self.confidence.to_dict(),
            "bounding_box_2d": self.bounding_box_2d.to_dict(),
            "bounding_box_3d": self.bounding_box_3d.to_dict(),
            "mesh": self.mesh.to_dict(),
        }


@dataclass
class TimingInfo:
    """Optional stage timings in milliseconds."""

    detection_ms: Optional[float] = None
    total3d_ms: Optional[float] = None
    total_ms: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "detection_ms": self.detection_ms,
            "total3d_ms": self.total3d_ms,
            "total_ms": self.total_ms,
        }


@dataclass
class SceneResult:
    """Top-level normalized result for one Total3D scene inference."""

    image: ImageInfo
    coordinate_system: CoordinateSystem
    camera: CameraData
    room_layout: RoomLayout
    objects: List[DetectedObject]
    timing: TimingInfo = field(default_factory=TimingInfo)
    warnings: List[str] = field(default_factory=list)
    schema_version: str = "1.0"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "image": self.image.to_dict(),
            "coordinate_system": self.coordinate_system.to_dict(),
            "camera": self.camera.to_dict(),
            "room_layout": self.room_layout.to_dict(),
            "objects": [obj.to_dict() for obj in self.objects],
            "timing": self.timing.to_dict(),
            "warnings": list(self.warnings),
        }

