"""Versioned contracts for future ARKit-to-extracted-frame association.

This module defines serialization only. It does not alter video extraction,
COLMAP, Nerfstudio, or any capture/upload behavior.
"""

from dataclasses import dataclass
from typing import Any, Dict, List


class CaptureMetadataValidationError(ValueError):
    """Raised when future capture metadata cannot be associated safely."""


@dataclass(frozen=True)
class VideoPresentationTime:
    value: int
    timescale: int

    def __post_init__(self) -> None:
        if self.timescale <= 0:
            raise CaptureMetadataValidationError("PTS timescale must be positive.")

    @property
    def seconds(self) -> float:
        return float(self.value) / float(self.timescale)

    def to_dict(self) -> Dict[str, int]:
        return {"value": self.value, "timescale": self.timescale}

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "VideoPresentationTime":
        return cls(value=int(payload["value"]), timescale=int(payload["timescale"]))


@dataclass(frozen=True)
class ExtractedFrameAssociation:
    image_file_name: str
    source_pts: VideoPresentationTime
    arkit_metadata_sample_id: str
    arkit_metadata_sample_index: int

    def __post_init__(self) -> None:
        if not self.image_file_name or "/" in self.image_file_name or "\\" in self.image_file_name:
            raise CaptureMetadataValidationError(
                "Extracted image name must be a nonempty file name, not a path."
            )
        if self.arkit_metadata_sample_index < 0:
            raise CaptureMetadataValidationError(
                "ARKit metadata sample index must not be negative."
            )
        if not self.arkit_metadata_sample_id:
            raise CaptureMetadataValidationError(
                "ARKit metadata sample identifier must not be empty."
            )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "imageFileName": self.image_file_name,
            "sourcePTS": self.source_pts.to_dict(),
            "arKitMetadataSampleID": self.arkit_metadata_sample_id,
            "arKitMetadataSampleIndex": self.arkit_metadata_sample_index,
        }

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "ExtractedFrameAssociation":
        return cls(
            image_file_name=str(payload["imageFileName"]),
            source_pts=VideoPresentationTime.from_dict(dict(payload["sourcePTS"])),
            arkit_metadata_sample_id=str(payload["arKitMetadataSampleID"]),
            arkit_metadata_sample_index=int(payload["arKitMetadataSampleIndex"]),
        )


@dataclass(frozen=True)
class FrameExtractionManifest:
    schema_version: str
    capture_id: str
    frames: List[ExtractedFrameAssociation]

    CURRENT_SCHEMA_VERSION = "1.0"

    def __post_init__(self) -> None:
        if self.schema_version != self.CURRENT_SCHEMA_VERSION:
            raise CaptureMetadataValidationError(
                "Unsupported extraction manifest schema version: %s"
                % self.schema_version
            )
        if not self.capture_id:
            raise CaptureMetadataValidationError("Capture identifier must not be empty.")
        names = [frame.image_file_name for frame in self.frames]
        if len(names) != len(set(names)):
            raise CaptureMetadataValidationError(
                "Extraction manifest image file names must be unique."
            )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "captureID": self.capture_id,
            "frames": [frame.to_dict() for frame in self.frames],
        }

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "FrameExtractionManifest":
        return cls(
            schema_version=str(payload["schemaVersion"]),
            capture_id=str(payload["captureID"]),
            frames=[
                ExtractedFrameAssociation.from_dict(dict(frame))
                for frame in payload.get("frames", [])
            ],
        )
