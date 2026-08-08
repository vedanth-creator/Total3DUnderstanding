import json
import unittest

from reconstruction.capture_metadata import (
    CaptureMetadataValidationError,
    ExtractedFrameAssociation,
    FrameExtractionManifest,
    VideoPresentationTime,
)


class CaptureMetadataContractTest(unittest.TestCase):
    def test_manifest_json_round_trip_preserves_exact_pts_and_identity(self) -> None:
        manifest = FrameExtractionManifest(
            schema_version="1.0",
            capture_id="741eda50-53e5-4b93-94bd-e70ee928c630",
            frames=[
                ExtractedFrameAssociation(
                    image_file_name="frame_00000042.jpg",
                    source_pts=VideoPresentationTime(value=1001, timescale=600),
                    arkit_metadata_sample_id="21db2aa9-6e83-4fe9-91c6-353285a43f3f",
                    arkit_metadata_sample_index=42,
                )
            ],
        )

        encoded = json.dumps(manifest.to_dict())
        payload = json.loads(encoded)
        decoded = FrameExtractionManifest.from_dict(json.loads(encoded))

        self.assertEqual(payload["schemaVersion"], "1.0")
        self.assertEqual(payload["frames"][0]["sourcePTS"], {"value": 1001, "timescale": 600})
        self.assertEqual(payload["frames"][0]["imageFileName"], "frame_00000042.jpg")
        self.assertEqual(decoded, manifest)
        self.assertEqual(decoded.frames[0].source_pts.value, 1001)
        self.assertEqual(decoded.frames[0].source_pts.timescale, 600)
        self.assertAlmostEqual(decoded.frames[0].source_pts.seconds, 1001 / 600)

    def test_invalid_pts_timescale_is_rejected(self) -> None:
        with self.assertRaisesRegex(CaptureMetadataValidationError, "positive"):
            VideoPresentationTime(value=1, timescale=0)

    def test_duplicate_image_names_are_rejected(self) -> None:
        frame = ExtractedFrameAssociation(
            image_file_name="frame_00000000.jpg",
            source_pts=VideoPresentationTime(value=0, timescale=600),
            arkit_metadata_sample_id="sample-0",
            arkit_metadata_sample_index=0,
        )
        with self.assertRaisesRegex(CaptureMetadataValidationError, "unique"):
            FrameExtractionManifest(
                schema_version="1.0",
                capture_id="capture-0",
                frames=[frame, frame],
            )


if __name__ == "__main__":
    unittest.main()
