import json
import unittest

from service.pipeline import (
    DecodedCamera,
    DecodedObject,
    DecodedRoomLayout,
    DecodedScene,
    FakeGPUClient,
    NoUsableDetectionsError,
    ScenePipeline,
)
from service.providers import (
    Detection,
    ScaledCanonicalIntrinsicsProvider,
    StaticDetectionProvider,
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


def make_decoded_scene() -> DecodedScene:
    return DecodedScene(
        coordinate_system_name="total3d_scene_frame_unverified",
        coordinate_system_units="units_unverified",
        camera=DecodedCamera(
            rotation=IDENTITY,
            pitch_radians=0.1,
            roll_radians=-0.05,
            pitch_bin_probability=0.91,
            roll_bin_probability=0.88,
        ),
        room_layout=DecodedRoomLayout(
            corners=CORNERS,
            centroid=(0.0, 0.0, 0.0),
            basis=IDENTITY,
            half_sizes=(1.0, 1.0, 1.0),
            orientation_bin_probability=0.93,
        ),
        objects=(
            DecodedObject(
                detection_index=0,
                object_id="object-0",
                corners=CORNERS,
                centroid=(0.0, 0.0, 0.0),
                basis=IDENTITY,
                half_sizes=(1.0, 1.0, 1.0),
                orientation_bin_probability=0.86,
                depth_bin_probability=0.78,
                mesh_uri="meshes/object-0.obj",
                mesh_coordinate_frame="total3d_scene_frame_unverified",
            ),
        ),
        total3d_ms=340.0,
    )


class ScenePipelineTest(unittest.TestCase):
    def setUp(self) -> None:
        self.detection = Detection(
            bbox_xyxy=(-5.0, 20.0, 100.0, 200.0),
            category_name="chair",
            nyu40_id=5,
            score=0.94,
        )
        self.gpu_client = FakeGPUClient(make_decoded_scene())
        self.pipeline = ScenePipeline(
            detection_provider=StaticDetectionProvider([self.detection]),
            intrinsics_provider=ScaledCanonicalIntrinsicsProvider(),
            gpu_client=self.gpu_client,
        )

    def test_constructs_scene_and_normalized_gpu_request(self) -> None:
        scene = self.pipeline.run(
            image_width=730,
            image_height=530,
            image_reference="requests/example.jpg",
        )

        self.assertEqual(scene.image.width, 730)
        self.assertEqual(scene.image.height, 530)
        self.assertEqual(len(scene.objects), 1)
        self.assertEqual(scene.objects[0].category.name, "chair")
        self.assertEqual(scene.objects[0].category.pix3d_id, 3)
        self.assertEqual(scene.objects[0].bounding_box_2d.xyxy[0], 0.0)

        request = self.gpu_client.last_request
        self.assertIsNotNone(request)
        assert request is not None
        self.assertEqual(request.image_reference, "requests/example.jpg")
        self.assertEqual(request.image_width, 730)
        self.assertEqual(request.image_height, 530)
        self.assertEqual(request.camera_intrinsics[0][0], 529.5)
        self.assertEqual(request.detections[0].bbox_xyxy[0], 0.0)

    def test_preserves_detector_confidence_separately(self) -> None:
        scene = self.pipeline.run(730, 530)

        confidence = scene.objects[0].confidence
        self.assertEqual(confidence.detector_category_probability, 0.94)
        self.assertNotEqual(
            confidence.detector_category_probability,
            confidence.orientation_bin_probability,
        )

    def test_preserves_model_probabilities(self) -> None:
        scene = self.pipeline.run(730, 530)

        self.assertEqual(
            scene.objects[0].confidence.orientation_bin_probability, 0.86
        )
        self.assertEqual(scene.objects[0].confidence.depth_bin_probability, 0.78)
        self.assertEqual(
            scene.camera.confidence.pitch_bin_probability, 0.91
        )
        self.assertEqual(scene.camera.confidence.roll_bin_probability, 0.88)
        self.assertEqual(
            scene.room_layout.confidence.orientation_bin_probability, 0.93
        )

    def test_propagates_assumed_intrinsics_warning(self) -> None:
        scene = self.pipeline.run(730, 530)

        self.assertTrue(
            any("assumed" in warning and "not calibrated" in warning
                for warning in scene.warnings)
        )

    def test_raises_when_no_usable_detections_remain(self) -> None:
        pipeline = ScenePipeline(
            detection_provider=StaticDetectionProvider([]),
            intrinsics_provider=ScaledCanonicalIntrinsicsProvider(),
            gpu_client=self.gpu_client,
        )

        with self.assertRaisesRegex(
            NoUsableDetectionsError, "No usable Total3D mesh detections"
        ):
            pipeline.run(730, 530)

        self.assertIsNone(self.gpu_client.last_request)

    def test_final_scene_is_json_serializable(self) -> None:
        scene = self.pipeline.run(730, 530)

        serialized = json.dumps(scene.to_dict())

        self.assertIsInstance(serialized, str)
        self.assertNotIn("aggregate_3d_confidence", serialized)


if __name__ == "__main__":
    unittest.main()
