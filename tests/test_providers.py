import unittest

from service.providers import (
    Detection,
    SUPPORTED_MESH_CATEGORIES,
    ScaledCanonicalIntrinsicsProvider,
    StaticDetectionProvider,
)


class StaticDetectionProviderTest(unittest.TestCase):
    def test_returns_valid_detection(self) -> None:
        provider = StaticDetectionProvider(
            [
                Detection(
                    bbox_xyxy=(10.0, 20.0, 100.0, 200.0),
                    category_name="chair",
                    nyu40_id=5,
                    score=0.9,
                )
            ]
        )

        detections = provider.get_detections(730, 530)

        self.assertEqual(len(detections), 1)
        self.assertEqual(detections[0].category_name, "chair")
        self.assertEqual(detections[0].bbox_xyxy, (10.0, 20.0, 100.0, 200.0))

    def test_clamps_box_to_image_dimensions(self) -> None:
        provider = StaticDetectionProvider(
            [
                Detection(
                    bbox_xyxy=(-10.0, -20.0, 750.0, 550.0),
                    category_name="table",
                    nyu40_id=7,
                    score=0.8,
                )
            ]
        )

        detection = provider.get_detections(730, 530)[0]

        self.assertEqual(detection.bbox_xyxy, (0.0, 0.0, 730.0, 530.0))

    def test_rejects_invalid_score(self) -> None:
        for score in (-0.01, 1.01, float("nan")):
            with self.subTest(score=score):
                provider = StaticDetectionProvider(
                    [
                        Detection(
                            bbox_xyxy=(10.0, 20.0, 100.0, 200.0),
                            category_name="chair",
                            nyu40_id=5,
                            score=score,
                        )
                    ]
                )

                with self.assertRaisesRegex(ValueError, "score must be between"):
                    provider.get_detections(730, 530)

    def test_rejects_zero_area_box_after_clamping(self) -> None:
        provider = StaticDetectionProvider(
            [
                Detection(
                    bbox_xyxy=(-20.0, 10.0, -10.0, 30.0),
                    category_name="chair",
                    nyu40_id=5,
                    score=0.9,
                )
            ]
        )

        with self.assertRaisesRegex(ValueError, "positive area"):
            provider.get_detections(730, 530)

    def test_rejects_unsupported_category(self) -> None:
        self.assertNotIn("lamp", SUPPORTED_MESH_CATEGORIES)
        provider = StaticDetectionProvider(
            [
                Detection(
                    bbox_xyxy=(10.0, 20.0, 100.0, 200.0),
                    category_name="lamp",
                    nyu40_id=35,
                    score=0.9,
                )
            ]
        )

        with self.assertRaisesRegex(ValueError, "Unsupported"):
            provider.get_detections(730, 530)


class ScaledCanonicalIntrinsicsProviderTest(unittest.TestCase):
    def test_scales_intrinsics_and_marks_them_assumed(self) -> None:
        provider = ScaledCanonicalIntrinsicsProvider()

        result = provider.get_intrinsics(1460, 1060)

        self.assertEqual(
            result.matrix,
            (
                (1059.0, 0.0, 730.0),
                (0.0, 1059.0, 530.0),
                (0.0, 0.0, 1.0),
            ),
        )
        self.assertTrue(result.metadata.assumed)
        self.assertFalse(result.metadata.calibrated)
        self.assertEqual(
            result.metadata.source, "scaled_canonical_demo_intrinsics"
        )


if __name__ == "__main__":
    unittest.main()
