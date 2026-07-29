import unittest


try:
    from fastapi.testclient import TestClient

    from service.app import create_app
except ModuleNotFoundError:
    TestClient = None
    create_app = None


VALID_PAYLOAD = {
    "image_id": "requests/example.jpg",
    "image_width": 730,
    "image_height": 530,
    "detections": [
        {
            "bbox_xyxy": [10.0, 20.0, 100.0, 200.0],
            "category_name": "chair",
            "nyu40_id": 5,
            "score": 0.94,
        }
    ],
}


@unittest.skipUnless(
    TestClient is not None and create_app is not None,
    "FastAPI test runtime is not installed.",
)
class SceneAPITest(unittest.TestCase):
    def setUp(self) -> None:
        assert TestClient is not None
        assert create_app is not None
        self.client = TestClient(create_app())

    def test_health_endpoint(self) -> None:
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(), {"status": "ok", "mode": "cpu-only-fake-gpu"}
        )

    def test_successful_inference(self) -> None:
        response = self.client.post("/v1/scenes/infer", json=VALID_PAYLOAD)

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["image"], {"width": 730, "height": 530})
        self.assertEqual(payload["objects"][0]["category"]["name"], "chair")
        self.assertEqual(
            payload["objects"][0]["confidence"][
                "detector_category_probability"
            ],
            0.94,
        )

    def test_invalid_dimensions(self) -> None:
        payload = dict(VALID_PAYLOAD)
        payload["image_width"] = 0

        response = self.client.post("/v1/scenes/infer", json=payload)

        self.assertEqual(response.status_code, 422)
        self.assertIn("image_width must be a positive integer", response.json()["detail"])

    def test_unsupported_category(self) -> None:
        payload = dict(VALID_PAYLOAD)
        payload["detections"] = [
            {
                "bbox_xyxy": [10.0, 20.0, 100.0, 200.0],
                "category_name": "lamp",
                "nyu40_id": 35,
                "score": 0.9,
            }
        ]

        response = self.client.post("/v1/scenes/infer", json=payload)

        self.assertEqual(response.status_code, 422)
        self.assertIn("Unsupported Total3D mesh category", response.json()["detail"])

    def test_no_usable_detections(self) -> None:
        payload = dict(VALID_PAYLOAD)
        payload["detections"] = []

        response = self.client.post("/v1/scenes/infer", json=payload)

        self.assertEqual(response.status_code, 422)
        self.assertIn("No usable Total3D mesh detections", response.json()["detail"])

    def test_json_response_structure(self) -> None:
        response = self.client.post("/v1/scenes/infer", json=VALID_PAYLOAD)

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["schema_version"], "1.0")
        self.assertIn("coordinate_system", payload)
        self.assertIn("camera", payload)
        self.assertIn("room_layout", payload)
        self.assertIn("objects", payload)
        self.assertIn("timing", payload)
        self.assertIn("warnings", payload)
        self.assertEqual(payload["objects"][0]["mesh"]["media_type"], "model/obj")


if __name__ == "__main__":
    unittest.main()
