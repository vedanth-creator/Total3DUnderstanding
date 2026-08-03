import json
import math
import shutil
import struct
import subprocess
import tarfile
import tempfile
import unittest
import zlib
from pathlib import Path

from reconstruction.nerfstudio_dataset import (
    DatasetOverwriteError,
    NerfstudioDatasetManifest,
    NerfstudioDatasetPreparer,
    RegisteredImageMissingError,
    UnsafeDatasetPathError,
)


def make_test_png(width, height):
    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    row = b"\0" + (b"\x80\x80\x80" * width)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(row * height))
        + chunk(b"IEND", b"")
    )


class FakeModelConverterRunner:
    def __init__(self, registered_names_by_model):
        self.registered_names_by_model = registered_names_by_model
        self.calls = []

    def run(self, arguments, log_path, cwd=None, environment=None):
        self.calls.append(
            {
                "arguments": list(arguments),
                "log_path": log_path,
                "cwd": cwd,
            }
        )
        input_path = Path(arguments[arguments.index("--input_path") + 1])
        output_path = Path(arguments[arguments.index("--output_path") + 1])
        names = self.registered_names_by_model[input_path.name]
        (output_path / "cameras.txt").write_text(
            "# cameras\n1 SIMPLE_RADIAL 1200 800 1000 600 400 0.01\n",
            encoding="utf-8",
        )
        lines = ["# images"]
        for image_id, name in enumerate(names, start=1):
            lines.append(
                "%d 1 0 0 0 0 0 0 1 %s" % (image_id, name)
            )
            lines.append("")
        (output_path / "images.txt").write_text(
            "\n".join(lines) + "\n",
            encoding="utf-8",
        )


class NerfstudioDatasetTest(unittest.TestCase):
    job_id = "2a09ee95-999b-4689-8844-cd5251d4333c"

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.jobs_root = self.root / "reconstruction" / "jobs"
        self.job_directory = self.jobs_root / self.job_id
        self.images_directory = self.job_directory / "images"
        self.sparse_directory = self.job_directory / "sparse"
        self.images_directory.mkdir(parents=True)
        self.sparse_directory.mkdir()
        (self.job_directory / "logs").mkdir()
        (self.job_directory / "database.db").write_bytes(b"database")
        (self.job_directory / "room-video.mov").write_bytes(b"video")

        test_image = make_test_png(1200, 800)
        for index in range(6):
            (self.images_directory / ("frame_%08d.png" % index)).write_bytes(
                test_image
            )

        self.registered = {
            "0": ["frame_00000000.png", "frame_00000001.png"],
            "1": [
                "frame_00000000.png",
                "frame_00000002.png",
                "frame_00000003.png",
                "frame_00000005.png",
            ],
            "2": [
                "frame_00000000.png",
                "frame_00000001.png",
                "frame_00000002.png",
                "frame_00000003.png",
            ],
        }
        self._make_model("0", registered=2, points=100)
        self._make_model("1", registered=4, points=500)
        self._make_model("2", registered=4, points=400)
        self.runner = FakeModelConverterRunner(self.registered)
        self.preparer = NerfstudioDatasetPreparer(process_runner=self.runner)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def _make_model(self, model_id, registered, points):
        model = self.sparse_directory / model_id
        model.mkdir()
        camera_payload = struct.pack("<QIiQQ4d", 1, 1, 2, 1200, 800, 1000, 600, 400, 0.01)
        (model / "cameras.bin").write_bytes(camera_payload)
        image_payload = bytearray(struct.pack("<Q", registered))
        for image_id, name in enumerate(self.registered[model_id], start=1):
            image_payload.extend(
                struct.pack(
                    "<I7dI",
                    image_id,
                    1.0,
                    0.0,
                    0.0,
                    0.0,
                    float(image_id),
                    2.0,
                    3.0,
                    1,
                )
            )
            image_payload.extend(name.encode("utf-8") + b"\0")
            image_payload.extend(struct.pack("<Q", 0))
        (model / "images.bin").write_bytes(bytes(image_payload))
        point_payload = bytearray(struct.pack("<Q", points))
        for point_id in range(1, points + 1):
            point_payload.extend(
                struct.pack(
                    "<Q3d3BdQ",
                    point_id,
                    float(point_id),
                    0.0,
                    0.0,
                    128,
                    128,
                    128,
                    0.1,
                    0,
                )
            )
        (model / "points3D.bin").write_bytes(bytes(point_payload))
        (model / "frames.bin").write_bytes(b"frames")
        (model / "rigs.bin").write_bytes(b"rigs")
        (model / "project.ini").write_text(
            "database_path=/private/source/database.db\n"
            "image_path=/private/source/images\n"
            "output_path=/private/source/sparse\n"
            "[General]\n",
            encoding="utf-8",
        )

    def prepare(self, **overrides):
        values = dict(
            job_id=self.job_id,
            workspace_root=self.jobs_root,
        )
        values.update(overrides)
        return self.preparer.prepare(**values)

    def test_selects_sparse_one_by_registered_images_then_points(self) -> None:
        selected = self.preparer.select_best_model(self.sparse_directory)

        self.assertEqual(selected.model_id, "1")
        self.assertEqual(selected.registered_image_count, 4)
        self.assertEqual(selected.sparse_point_count, 500)

    def test_only_registered_images_are_copied(self) -> None:
        prepared = self.prepare()

        copied = sorted(
            path.name
            for path in (prepared.dataset_directory / "images").iterdir()
        )
        self.assertEqual(copied, sorted(self.registered["1"]))
        self.assertNotIn("frame_00000004.png", copied)
        self.assertEqual(prepared.manifest.extracted_frame_count, 6)
        self.assertEqual(prepared.manifest.copied_image_count, 4)

    def test_transforms_json_preserves_intrinsics_names_and_opengl_poses(self) -> None:
        prepared = self.prepare()
        transforms = json.loads(
            (prepared.dataset_directory / "transforms.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertEqual(transforms["camera_model"], "OPENCV")
        self.assertEqual(transforms["w"], 1200)
        self.assertEqual(transforms["h"], 800)
        self.assertEqual(transforms["fl_x"], 1000)
        self.assertEqual(transforms["fl_y"], 1000)
        self.assertEqual(transforms["cx"], 600)
        self.assertEqual(transforms["cy"], 400)
        self.assertEqual(transforms["k1"], 0.01)
        self.assertEqual(transforms["k2"], 0.0)
        self.assertEqual(transforms["p1"], 0.0)
        self.assertEqual(transforms["p2"], 0.0)
        self.assertAlmostEqual(
            transforms["camera_angle_x"],
            2.0 * math.atan(1200 / 2000),
        )
        self.assertEqual(
            [frame["file_path"] for frame in transforms["frames"]],
            ["images/" + name for name in self.registered["1"]],
        )
        self.assertEqual(
            transforms["frames"][0]["transform_matrix"],
            [
                [1.0, -0.0, -0.0, -1.0],
                [0.0, -0.0, -1.0, -3.0],
                [-0.0, 1.0, 0.0, 2.0],
                [0.0, 0.0, 0.0, 1.0],
            ],
        )
        self.assertEqual(
            transforms["applied_transform"],
            [
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 0.0, 1.0, 0.0],
                [0.0, -1.0, 0.0, 0.0],
            ],
        )
        self.assertEqual(transforms["ply_file_path"], "sparse_pc.ply")
        point_cloud = (prepared.dataset_directory / "sparse_pc.ply").read_text()
        self.assertIn("element vertex 500", point_cloud)

    def test_missing_registered_image_fails_clearly(self) -> None:
        (self.images_directory / "frame_00000005.png").unlink()

        with self.assertRaises(RegisteredImageMissingError) as context:
            self.prepare()

        self.assertEqual(context.exception.missing_images, ("frame_00000005.png",))
        self.assertFalse((self.job_directory / "nerfstudio-data").exists())

    def test_selected_model_is_normalized_to_colmap_sparse_zero(self) -> None:
        prepared = self.prepare()
        normalized = prepared.dataset_directory / "colmap" / "sparse" / "0"

        for filename in (
            "cameras.bin",
            "images.bin",
            "points3D.bin",
            "frames.bin",
            "rigs.bin",
        ):
            self.assertEqual(
                (normalized / filename).read_bytes(),
                (self.sparse_directory / "1" / filename).read_bytes(),
            )
        project_ini = (normalized / "project.ini").read_text(encoding="utf-8")
        self.assertIn("database_path=\n", project_ini)
        self.assertIn("image_path=../../../images\n", project_ini)
        self.assertIn("output_path=.\n", project_ini)
        self.assertNotIn("/private/source", project_ini)

    def test_archive_contains_only_portable_dataset_tree(self) -> None:
        prepared = self.prepare(archive=True)

        self.assertTrue(prepared.archive_path.is_file())
        with tarfile.open(prepared.archive_path, "r:gz") as archive:
            names = set(archive.getnames())
        self.assertIn("nerfstudio-data/dataset-manifest.json", names)
        self.assertIn("nerfstudio-data/transforms.json", names)
        self.assertIn("nerfstudio-data/sparse_pc.ply", names)
        self.assertIn(
            "nerfstudio-data/colmap/sparse/0/images.bin",
            names,
        )
        self.assertFalse(any("database.db" in name for name in names))
        self.assertFalse(any("room-video.mov" in name for name in names))
        self.assertFalse(any("logs" in name for name in names))
        self.assertFalse(any("sparse/1" in name or "sparse/2" in name for name in names))
        self.assertFalse(any(name.startswith("/") for name in names))

    def test_manifest_paths_are_relative_and_serializable(self) -> None:
        prepared = self.prepare()
        payload = prepared.manifest.to_dict()

        json.dumps(payload)
        self.assertEqual(payload["selected_sparse_model_id"], "1")
        self.assertEqual(payload["registered_image_count"], 4)
        self.assertEqual(payload["sparse_point_count"], 500)
        self.assertEqual(payload["camera_count"], 1)
        for key in (
            "source_job_directory",
            "selected_sparse_model_path",
            "dataset_directory",
        ):
            self.assertFalse(Path(payload[key]).is_absolute())
        on_disk = json.loads(
            (prepared.dataset_directory / "dataset-manifest.json").read_text()
        )
        self.assertEqual(on_disk, payload)

    def test_rejects_unsafe_job_id(self) -> None:
        with self.assertRaises(UnsafeDatasetPathError):
            self.preparer.prepare(
                job_id="../escape",
                workspace_root=self.jobs_root,
            )

    def test_refuses_to_overwrite_without_force(self) -> None:
        first = self.prepare()
        marker = first.dataset_directory / "keep.txt"
        marker.write_text("keep", encoding="utf-8")

        with self.assertRaises(DatasetOverwriteError):
            self.prepare()

        self.assertTrue(marker.is_file())

    def test_link_images_uses_relative_symlinks(self) -> None:
        prepared = self.prepare(link_images=True)
        linked = prepared.dataset_directory / "images" / self.registered["1"][0]

        self.assertTrue(linked.is_symlink())
        self.assertFalse(Path(linked.readlink()).is_absolute())
        self.assertTrue(linked.is_file())
        self.assertTrue(prepared.manifest.warnings)

    def test_manifest_dataclass_serializes_unavailable_point_count_as_null(self) -> None:
        manifest = NerfstudioDatasetManifest(
            job_id="job",
            source_job_directory="..",
            selected_sparse_model_id="0",
            selected_sparse_model_path="../sparse/0",
            extracted_frame_count=1,
            registered_image_count=1,
            copied_image_count=1,
            sparse_point_count=None,
            camera_count=1,
            missing_images=[],
            dataset_directory=".",
        )

        payload = json.loads(json.dumps(manifest.to_dict()))
        self.assertIsNone(payload["sparse_point_count"])

    def test_ns_train_splatfacto_accepts_prepared_dataset_when_installed(self) -> None:
        ns_train = shutil.which("ns-train")
        if ns_train is None:
            self.skipTest("ns-train is not installed in this environment")
        prepared = self.prepare()

        completed = subprocess.run(
            [
                ns_train,
                "splatfacto",
                "--data",
                str(prepared.dataset_directory),
                "--max-num-iterations",
                "0",
                "--vis",
                "tensorboard",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=180,
        )

        self.assertEqual(
            completed.returncode,
            0,
            msg="ns-train rejected the prepared dataset:\n%s\n%s"
            % (completed.stdout, completed.stderr),
        )


if __name__ == "__main__":
    unittest.main()
