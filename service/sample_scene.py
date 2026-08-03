"""Deterministic normalized sample scene returned by fake reconstruction."""

import math
from typing import List, Optional, Sequence

from service.api_schemas import RoomScanJob
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


IDENTITY = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
]


def _basis(yaw_degrees: float) -> List[List[float]]:
    angle = math.radians(yaw_degrees)
    return [
        [math.cos(angle), 0.0, math.sin(angle)],
        [0.0, 1.0, 0.0],
        [-math.sin(angle), 0.0, math.cos(angle)],
    ]


def _corners(
    centroid: Sequence[float], half_sizes: Sequence[float]
) -> List[List[float]]:
    cx, cy, cz = centroid
    hx, hy, hz = half_sizes
    return [
        [cx - hx, cy + hy, cz - hz],
        [cx - hx, cy + hy, cz + hz],
        [cx + hx, cy + hy, cz + hz],
        [cx + hx, cy + hy, cz - hz],
        [cx - hx, cy - hy, cz - hz],
        [cx - hx, cy - hy, cz + hz],
        [cx + hx, cy - hy, cz + hz],
        [cx + hx, cy - hy, cz - hz],
    ]


def _sample_object(
    object_id: str,
    name: str,
    nyu40_id: Optional[int],
    pix3d_id: Optional[int],
    centroid: Sequence[float],
    half_sizes: Sequence[float],
    yaw_degrees: float,
) -> DetectedObject:
    return DetectedObject(
        object_id=object_id,
        category=ObjectCategory(name=name, nyu40_id=nyu40_id, pix3d_id=pix3d_id),
        confidence=ObjectConfidence(
            detector_category_probability=0.0,
            orientation_bin_probability=None,
            depth_bin_probability=None,
        ),
        bounding_box_2d=BoundingBox2D(xyxy=[0.0, 0.0, 0.0, 0.0]),
        bounding_box_3d=BoundingBox3D(
            corners=_corners(centroid, half_sizes),
            centroid=list(centroid),
            basis=_basis(yaw_degrees),
            half_sizes=list(half_sizes),
        ),
        mesh=MeshReference(
            uri="sample://placeholder-box/%s" % object_id,
            media_type="application/x-placeholder-box",
            coordinate_frame="sample_realitykit_room_frame",
        ),
    )


def make_sample_scene(job: RoomScanJob) -> SceneResult:
    """Return sample geometry only; no uploaded-video inference is performed."""

    width = job.client_metadata.width or 1920
    height = job.client_metadata.height or 1080
    room_half_sizes = [2.9, 1.35, 2.1]
    room_centroid = [0.0, 1.35, 0.0]
    objects = [
        _sample_object(
            "74afe875-861c-4cb5-8427-a34ed03e0c74",
            "sofa",
            6,
            5,
            [0.0, 0.41, 1.13],
            [1.2, 0.41, 0.45],
            0.0,
        ),
        _sample_object(
            "a1891890-3a4c-485b-8e0b-f4d2ec868126",
            "table",
            7,
            6,
            [0.0, 0.19, -0.08],
            [0.625, 0.19, 0.325],
            0.0,
        ),
        _sample_object(
            "d9d2f5f3-2444-4ba2-8d79-2ca863c3ea10",
            "chair",
            5,
            3,
            [-1.74, 0.46, -0.63],
            [0.425, 0.46, 0.425],
            28.0,
        ),
        _sample_object(
            "8464300d-c270-429f-b861-1a95349da5c3",
            "plant",
            None,
            None,
            [1.972, 0.825, -1.26],
            [0.275, 0.825, 0.275],
            0.0,
        ),
    ]

    return SceneResult(
        image=ImageInfo(width=width, height=height),
        coordinate_system=CoordinateSystem(
            name="sample_realitykit_room_frame",
            units="meters",
            handedness="right_handed",
            axis_convention="X right, Y up, Z toward open room front",
        ),
        camera=CameraData(
            intrinsics=[
                [float(max(width, height)), 0.0, width / 2.0],
                [0.0, float(max(width, height)), height / 2.0],
                [0.0, 0.0, 1.0],
            ],
            rotation=IDENTITY,
            pitch_radians=0.0,
            roll_radians=0.0,
            confidence=CameraConfidence(),
        ),
        room_layout=RoomLayout(
            corners=_corners(room_centroid, room_half_sizes),
            centroid=room_centroid,
            basis=IDENTITY,
            half_sizes=room_half_sizes,
            confidence=LayoutConfidence(),
        ),
        objects=objects,
        timing=TimingInfo(),
        warnings=[
            "This is deterministic sample geometry; the uploaded video was not reconstructed.",
            "Furniture meshes are placeholder box references.",
        ],
    )
