import json
import unittest

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

CORNERS = [
    [-1.0, 1.0, -1.0],
    [-1.0, 1.0, 1.0],
    [1.0, 1.0, 1.0],
    [1.0, 1.0, -1.0],
    [-1.0, -1.0, -1.0],
    [-1.0, -1.0, 1.0],
    [1.0, -1.0, 1.0],
    [1.0, -1.0, -1.0],
]


class SceneResultContractTest(unittest.TestCase):
    def test_example_scene_is_json_serializable(self) -> None:
        box_3d = BoundingBox3D(
            corners=CORNERS,
            centroid=[0.0, 0.0, 0.0],
            basis=IDENTITY,
            half_sizes=[1.0, 1.0, 1.0],
        )
        scene = SceneResult(
            image=ImageInfo(width=730, height=530),
            coordinate_system=CoordinateSystem(
                name="producer_declared_scene_frame",
                units="producer_declared_units",
            ),
            camera=CameraData(
                intrinsics=[
                    [529.5, 0.0, 365.0],
                    [0.0, 529.5, 265.0],
                    [0.0, 0.0, 1.0],
                ],
                rotation=IDENTITY,
                pitch_radians=0.1,
                roll_radians=-0.05,
                confidence=CameraConfidence(
                    pitch_bin_probability=0.91,
                    roll_bin_probability=0.88,
                ),
            ),
            room_layout=RoomLayout(
                corners=CORNERS,
                centroid=[0.0, 0.0, 0.0],
                basis=IDENTITY,
                half_sizes=[1.0, 1.0, 1.0],
                confidence=LayoutConfidence(
                    orientation_bin_probability=0.93
                ),
            ),
            objects=[
                DetectedObject(
                    object_id="object-0",
                    category=ObjectCategory(
                        name="chair", nyu40_id=5, pix3d_id=3
                    ),
                    confidence=ObjectConfidence(
                        detector_category_probability=0.94,
                        orientation_bin_probability=0.86,
                        depth_bin_probability=0.78,
                    ),
                    bounding_box_2d=BoundingBox2D(
                        xyxy=[99.0, 210.0, 226.0, 393.0]
                    ),
                    bounding_box_3d=box_3d,
                    mesh=MeshReference(
                        uri="meshes/object-0.obj",
                        coordinate_frame="producer_declared_scene_frame",
                    ),
                )
            ],
            timing=TimingInfo(
                detection_ms=12.5,
                total3d_ms=340.0,
                total_ms=352.5,
            ),
            warnings=["Coordinate conventions are not yet verified."],
        )

        payload = scene.to_dict()
        serialized = json.dumps(payload)

        self.assertIsInstance(serialized, str)
        self.assertEqual(payload["image"], {"width": 730, "height": 530})
        self.assertEqual(
            payload["objects"][0]["confidence"][
                "detector_category_probability"
            ],
            0.94,
        )
        self.assertNotIn("aggregate_3d_confidence", serialized)


if __name__ == "__main__":
    unittest.main()
