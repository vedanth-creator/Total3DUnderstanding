"""CPU-only provider interfaces and validation for Total3D inputs.

The supported category table below is derived from ``NYU40CLASSES``,
``NYU37_TO_PIX3D_CLS_MAPPING``, and ``RECON_3D_CLS`` in
``configs/data_config.py``.  Values are copied here deliberately so importing
this module does not import NumPy or any legacy model dependencies.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
import math
from types import MappingProxyType
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple


BoundingBox = Tuple[float, float, float, float]
IntrinsicMatrix = Tuple[
    Tuple[float, float, float],
    Tuple[float, float, float],
    Tuple[float, float, float],
]


@dataclass(frozen=True)
class SupportedCategory:
    """Repository class identifiers for a mesh-supported category."""

    nyu40_id: int
    pix3d_id: int


# Only IDs listed by RECON_3D_CLS are included. The spelling of
# "refridgerator" is retained because it is the repository's canonical label.
SUPPORTED_MESH_CATEGORIES: Mapping[str, SupportedCategory] = MappingProxyType(
    {
        "cabinet": SupportedCategory(nyu40_id=3, pix3d_id=8),
        "bed": SupportedCategory(nyu40_id=4, pix3d_id=1),
        "chair": SupportedCategory(nyu40_id=5, pix3d_id=3),
        "sofa": SupportedCategory(nyu40_id=6, pix3d_id=5),
        "table": SupportedCategory(nyu40_id=7, pix3d_id=6),
        "door": SupportedCategory(nyu40_id=8, pix3d_id=8),
        "bookshelf": SupportedCategory(nyu40_id=10, pix3d_id=2),
        "desk": SupportedCategory(nyu40_id=14, pix3d_id=4),
        "shelves": SupportedCategory(nyu40_id=15, pix3d_id=2),
        "dresser": SupportedCategory(nyu40_id=17, pix3d_id=8),
        "refridgerator": SupportedCategory(nyu40_id=24, pix3d_id=8),
        "television": SupportedCategory(nyu40_id=25, pix3d_id=8),
        "box": SupportedCategory(nyu40_id=29, pix3d_id=8),
        "whiteboard": SupportedCategory(nyu40_id=30, pix3d_id=8),
        "night_stand": SupportedCategory(nyu40_id=32, pix3d_id=8),
    }
)


@dataclass(frozen=True)
class Detection:
    """One external 2D detection prepared for Total3D preprocessing."""

    bbox_xyxy: BoundingBox
    category_name: str
    nyu40_id: int
    score: float

    def to_dict(self) -> Dict[str, Any]:
        return {
            "bbox_xyxy": [float(value) for value in self.bbox_xyxy],
            "category_name": self.category_name,
            "nyu40_id": self.nyu40_id,
            "score": float(self.score),
        }


def validate_detection(
    detection: Detection, image_width: int, image_height: int
) -> Detection:
    """Validate and clamp one detection to the source image dimensions.

    A new ``Detection`` is returned so provider-owned inputs are not mutated.
    Boxes use ``[x_min, y_min, x_max, y_max]`` coordinates.
    """

    if image_width <= 0 or image_height <= 0:
        raise ValueError("Image width and height must be positive.")

    if len(detection.bbox_xyxy) != 4:
        raise ValueError("Detection bounding boxes must contain four values.")

    try:
        x_min, y_min, x_max, y_max = (
            float(value) for value in detection.bbox_xyxy
        )
        score = float(detection.score)
    except (TypeError, ValueError) as error:
        raise ValueError("Detection box coordinates and score must be numeric.") from error

    if not all(math.isfinite(value) for value in (x_min, y_min, x_max, y_max)):
        raise ValueError("Detection bounding box coordinates must be finite.")
    if not math.isfinite(score) or not 0.0 <= score <= 1.0:
        raise ValueError("Detection score must be between 0 and 1.")

    category = SUPPORTED_MESH_CATEGORIES.get(detection.category_name)
    if category is None:
        raise ValueError(
            "Unsupported Total3D mesh category: %s" % detection.category_name
        )
    if detection.nyu40_id != category.nyu40_id:
        raise ValueError(
            "Category %s must use NYU40 ID %d."
            % (detection.category_name, category.nyu40_id)
        )

    clamped = (
        min(max(x_min, 0.0), float(image_width)),
        min(max(y_min, 0.0), float(image_height)),
        min(max(x_max, 0.0), float(image_width)),
        min(max(y_max, 0.0), float(image_height)),
    )
    if clamped[2] <= clamped[0] or clamped[3] <= clamped[1]:
        raise ValueError("Detection bounding box must have positive area.")

    return Detection(
        bbox_xyxy=clamped,
        category_name=detection.category_name,
        nyu40_id=detection.nyu40_id,
        score=score,
    )


class DetectionProvider(ABC):
    """Abstract source of validated detections for one image."""

    @abstractmethod
    def get_detections(
        self, image_width: int, image_height: int
    ) -> List[Detection]:
        """Return detections for an image with the supplied dimensions."""


class StaticDetectionProvider(DetectionProvider):
    """Provider that validates and returns a predefined detection sequence."""

    def __init__(self, detections: Sequence[Detection]) -> None:
        self._detections = tuple(detections)

    def get_detections(
        self, image_width: int, image_height: int
    ) -> List[Detection]:
        return [
            validate_detection(detection, image_width, image_height)
            for detection in self._detections
        ]


@dataclass(frozen=True)
class IntrinsicsMetadata:
    """Provenance metadata for a camera intrinsic matrix."""

    source: str
    assumed: bool
    calibrated: bool
    canonical_image_width: int
    canonical_image_height: int

    def to_dict(self) -> Dict[str, Any]:
        return {
            "source": self.source,
            "assumed": self.assumed,
            "calibrated": self.calibrated,
            "canonical_image_width": self.canonical_image_width,
            "canonical_image_height": self.canonical_image_height,
        }


@dataclass(frozen=True)
class IntrinsicsResult:
    """A camera intrinsic matrix and its provenance metadata."""

    matrix: IntrinsicMatrix
    metadata: IntrinsicsMetadata

    def to_dict(self) -> Dict[str, Any]:
        return {
            "matrix": [[float(value) for value in row] for row in self.matrix],
            "metadata": self.metadata.to_dict(),
        }


class IntrinsicsProvider(ABC):
    """Abstract source of camera intrinsics for one image."""

    @abstractmethod
    def get_intrinsics(
        self, image_width: int, image_height: int
    ) -> IntrinsicsResult:
        """Return camera intrinsics for the supplied image dimensions."""


class ScaledCanonicalIntrinsicsProvider(IntrinsicsProvider):
    """Scale assumed canonical intrinsics to the actual image dimensions.

    The defaults come from the repository demo inputs, whose images are
    730-by-530 pixels and whose camera matrix uses focal lengths 529.5 and
    principal point (365, 265). This is an explicit assumption, not a camera
    calibration result.
    """

    def __init__(
        self,
        canonical_matrix: Optional[IntrinsicMatrix] = None,
        canonical_image_width: int = 730,
        canonical_image_height: int = 530,
    ) -> None:
        if canonical_image_width <= 0 or canonical_image_height <= 0:
            raise ValueError("Canonical image dimensions must be positive.")
        self._canonical_matrix = canonical_matrix or (
            (529.5, 0.0, 365.0),
            (0.0, 529.5, 265.0),
            (0.0, 0.0, 1.0),
        )
        self._canonical_image_width = canonical_image_width
        self._canonical_image_height = canonical_image_height

    def get_intrinsics(
        self, image_width: int, image_height: int
    ) -> IntrinsicsResult:
        if image_width <= 0 or image_height <= 0:
            raise ValueError("Image width and height must be positive.")

        scale_x = float(image_width) / self._canonical_image_width
        scale_y = float(image_height) / self._canonical_image_height
        matrix = self._canonical_matrix
        scaled: IntrinsicMatrix = (
            tuple(float(value) * scale_x for value in matrix[0]),
            tuple(float(value) * scale_y for value in matrix[1]),
            tuple(float(value) for value in matrix[2]),
        )  # type: ignore[assignment]

        return IntrinsicsResult(
            matrix=scaled,
            metadata=IntrinsicsMetadata(
                source="scaled_canonical_demo_intrinsics",
                assumed=True,
                calibrated=False,
                canonical_image_width=self._canonical_image_width,
                canonical_image_height=self._canonical_image_height,
            ),
        )

