import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from reconstruction.colmap_runner import ColmapRunner
from reconstruction.config import ReconstructionConfig
from reconstruction.frame_extractor import FrameExtractor
from reconstruction.process_runner import (
    CommandExecutionError,
    MissingExecutableError,
    ProcessRunner,
)
from reconstruction.result_parser import ReconstructionResultParser
from reconstruction.worker import (
    ColmapReconstructionWorker,
    ReconstructionWorkspaceError,
)


class RecordingProcessRunner:
    def __init__(self) -> None:
        self.calls = []

    def run(self, arguments, log_path, cwd=None, environment=None):
        self.calls.append(
            {
                "arguments": list(arguments),
                "log_path": log_path,
                "cwd": cwd,
                "environment": environment,
            }
        )


class ReconstructionPackageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.workspace_root = Path(self.temporary_directory.name).resolve()
        self.video_path = self.workspace_root / "room.mov"
        self.video_path.write_bytes(b"mock-video")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def config(self, job_id="job-123", cpu_only=True, **overrides):
        values = dict(
            job_id=job_id,
            video_path=self.video_path,
            workspace_root=self.workspace_root,
            frames_per_second=2.5,
            max_image_size=1200,
            cpu_only=cpu_only,
            colmap_binary="test-colmap",
            ffmpeg_binary="test-ffmpeg",
        )
        values.update(overrides)
        return ReconstructionConfig(**values)

    def test_config_uses_safe_job_layout_and_rejects_traversal(self) -> None:
        config = self.config()

        self.assertEqual(
            config.job_directory,
            self.workspace_root / "job-123",
        )
        self.assertEqual(config.database_path, config.job_directory / "database.db")
        with self.assertRaises(ValueError):
            self.config(job_id="../escape")

    def test_process_runner_reports_missing_executable(self) -> None:
        with mock.patch("reconstruction.process_runner.shutil.which", return_value=None):
            with self.assertRaisesRegex(MissingExecutableError, "was not found"):
                ProcessRunner().run(
                    ["missing-colmap", "mapper"],
                    self.workspace_root / "missing.log",
                )

    def test_process_runner_uses_argument_array_and_never_shell_true(self) -> None:
        completed = subprocess.CompletedProcess(["/mock/ffmpeg"], 0)
        with mock.patch(
            "reconstruction.process_runner.shutil.which",
            return_value="/mock/ffmpeg",
        ), mock.patch(
            "reconstruction.process_runner.subprocess.run",
            return_value=completed,
        ) as run:
            ProcessRunner().run(
                ["ffmpeg", "-version"],
                self.workspace_root / "ffmpeg.log",
            )

        positional_arguments = run.call_args.args[0]
        keyword_arguments = run.call_args.kwargs
        self.assertEqual(positional_arguments, ["/mock/ffmpeg", "-version"])
        self.assertIs(keyword_arguments["shell"], False)
        self.assertIs(keyword_arguments["check"], False)

    def test_process_runner_raises_clear_failed_command_error(self) -> None:
        completed = subprocess.CompletedProcess(["/mock/colmap"], 7)
        log_path = self.workspace_root / "mapper.log"
        with mock.patch(
            "reconstruction.process_runner.shutil.which",
            return_value="/mock/colmap",
        ), mock.patch(
            "reconstruction.process_runner.subprocess.run",
            return_value=completed,
        ):
            with self.assertRaises(CommandExecutionError) as context:
                ProcessRunner().run(["colmap", "mapper"], log_path)

        self.assertEqual(context.exception.return_code, 7)
        self.assertEqual(context.exception.log_path, log_path)
        self.assertIn("exit code 7", str(context.exception))

    def test_frame_extractor_builds_ordered_zero_padded_output(self) -> None:
        config = self.config()
        config.prepare_directories()
        (config.images_directory / "frame_00000001.jpg").write_bytes(b"one")
        (config.images_directory / "frame_00000000.jpg").write_bytes(b"zero")
        runner = RecordingProcessRunner()

        frames = FrameExtractor(runner).extract(config)

        arguments = runner.calls[0]["arguments"]
        self.assertIn("-start_number", arguments)
        self.assertEqual(arguments[-1], str(config.images_directory / "frame_%08d.jpg"))
        self.assertEqual(
            [frame.name for frame in frames],
            ["frame_00000000.jpg", "frame_00000001.jpg"],
        )

    def test_relative_and_absolute_workspace_roots_append_only_job_id(self) -> None:
        absolute_root = self.workspace_root / "absolute-jobs"
        absolute_config = ReconstructionConfig(
            job_id="absolute-job",
            video_path=self.video_path,
            workspace_root=absolute_root,
        )
        self.assertEqual(
            absolute_config.job_directory,
            absolute_root.resolve() / "absolute-job",
        )

        with tempfile.TemporaryDirectory(dir=Path.cwd()) as local_directory:
            relative_root = Path(local_directory).relative_to(Path.cwd()) / "relative-jobs"
            relative_config = ReconstructionConfig(
                job_id="relative-job",
                video_path=self.video_path,
                workspace_root=relative_root,
            )
            self.assertEqual(
                relative_config.job_directory,
                (Path.cwd() / relative_root / "relative-job").resolve(),
            )
            self.assertNotIn(
                "reconstruction/jobs/reconstruction/jobs",
                str(relative_config.job_directory),
            )

    def test_colmap_4_1_1_cpu_commands_use_supported_options(self) -> None:
        config = self.config(cpu_only=True)
        config.prepare_directories()
        runner = RecordingProcessRunner()

        ColmapRunner(runner).run(config, matcher="sequential")

        self.assertEqual(
            [call["arguments"][1] for call in runner.calls],
            ["feature_extractor", "sequential_matcher", "mapper"],
        )
        feature_arguments = runner.calls[0]["arguments"]
        matcher_arguments = runner.calls[1]["arguments"]
        self.assertIn("--ImageReader.single_camera", feature_arguments)
        self.assertEqual(
            feature_arguments[feature_arguments.index("--ImageReader.single_camera") + 1],
            "1",
        )
        self.assertIn("--FeatureExtraction.max_image_size", feature_arguments)
        self.assertIn("--FeatureExtraction.use_gpu", feature_arguments)
        self.assertIn("--FeatureMatching.use_gpu", matcher_arguments)
        mapper_arguments = runner.calls[2]["arguments"]
        self.assertIn("--Mapper.init_min_num_inliers", mapper_arguments)
        self.assertIn("--Mapper.init_min_tri_angle", mapper_arguments)
        self.assertIn("--Mapper.ba_use_gpu", mapper_arguments)
        self.assertNotIn("--SiftExtraction.max_image_size", feature_arguments)
        self.assertNotIn("--SiftExtraction.use_gpu", feature_arguments)
        self.assertNotIn("--SiftMatching.use_gpu", matcher_arguments)

    def test_gpu_flags_are_omitted_without_cpu_only(self) -> None:
        config = self.config(cpu_only=False)
        config.prepare_directories()
        runner = RecordingProcessRunner()

        ColmapRunner(runner).run(config, matcher="sequential")

        all_arguments = [argument for call in runner.calls for argument in call["arguments"]]
        self.assertNotIn("--FeatureExtraction.use_gpu", all_arguments)
        self.assertNotIn("--FeatureMatching.use_gpu", all_arguments)

    def test_auto_matcher_selection(self) -> None:
        config = self.config(matcher="auto")

        self.assertEqual(config.matcher_for_frame_count(1), "exhaustive")
        self.assertEqual(config.matcher_for_frame_count(150), "exhaustive")
        self.assertEqual(config.matcher_for_frame_count(151), "sequential")

    def test_exhaustive_matcher_command_uses_supported_guided_cpu_options(self) -> None:
        config = self.config(cpu_only=True, guided_matching=True)
        config.prepare_directories()
        runner = RecordingProcessRunner()

        ColmapRunner(runner).run(config, matcher="exhaustive")

        matcher_call = runner.calls[1]
        arguments = matcher_call["arguments"]
        self.assertEqual(arguments[1], "exhaustive_matcher")
        self.assertIn("--FeatureMatching.use_gpu", arguments)
        self.assertIn("--FeatureMatching.guided_matching", arguments)
        self.assertNotIn("--SiftMatching.use_gpu", arguments)
        self.assertEqual(
            matcher_call["log_path"].name,
            "colmap-exhaustive-matcher.log",
        )

    def test_sequential_matcher_command_is_selected_explicitly(self) -> None:
        config = self.config(matcher="sequential")
        config.prepare_directories()
        runner = RecordingProcessRunner()

        ColmapRunner(runner).run(config, matcher="sequential")

        self.assertEqual(runner.calls[1]["arguments"][1], "sequential_matcher")
        self.assertEqual(
            runner.calls[1]["log_path"].name,
            "colmap-sequential-matcher.log",
        )

    def test_result_parser_writes_reconstruction_json(self) -> None:
        config = self.config()
        config.prepare_directories()
        config.database_path.write_bytes(b"sqlite")
        model_directory = config.sparse_directory / "0"
        model_directory.mkdir()
        (model_directory / "cameras.txt").write_text("# cameras\n", encoding="utf-8")
        (model_directory / "points3D.txt").write_text("# points\n", encoding="utf-8")
        (model_directory / "images.txt").write_text(
            "# images\n"
            "1 1 0 0 0 0 0 0 1 frame_00000000.jpg\n"
            "\n"
            "2 1 0 0 0 0 0 0 1 frame_00000001.jpg\n"
            "1.0 2.0 -1\n",
            encoding="utf-8",
        )

        result = ReconstructionResultParser().parse(
            config,
            extracted_frame_count=20,
            matcher_used="exhaustive",
            retry_attempted=True,
            retry_succeeded=True,
            reconstruction_duration_seconds=1.25,
        )

        self.assertEqual(result.status, "completed")
        self.assertEqual(result.sparse_models[0].registered_image_count, 2)
        self.assertEqual(result.sparse_point_count, 0)
        self.assertEqual(result.matcher_used, "exhaustive")
        self.assertTrue(result.retry_attempted)
        self.assertTrue(result.retry_succeeded)
        self.assertEqual(result.reconstruction_duration_seconds, 1.25)
        self.assertTrue(result.recommendations)
        self.assertTrue(config.result_path.is_file())
        payload = json.loads(config.result_path.read_text())
        self.assertEqual(payload["registered_image_count"], 2)
        self.assertEqual(payload["sparse_point_count"], 0)
        self.assertEqual(payload["matcher_used"], "exhaustive")
        self.assertIn("recommendations", payload)

    def test_worker_is_fully_testable_without_external_tools(self) -> None:
        config = self.config()

        class FakeExtractor:
            def extract(self, worker_config):
                frame = worker_config.images_directory / "frame_00000000.jpg"
                frame.write_bytes(b"image")
                return [frame]

        class FakeColmap:
            def run(self, worker_config, matcher, log_prefix=""):
                worker_config.database_path.write_bytes(b"sqlite")
                model = worker_config.sparse_directory / "0"
                model.mkdir()
                (model / "cameras.bin").write_bytes(struct.pack("<Q", 1))
                (model / "images.bin").write_bytes(struct.pack("<Q", 1))
                (model / "points3D.bin").write_bytes(struct.pack("<Q", 25))

        worker = ColmapReconstructionWorker(
            frame_extractor=FakeExtractor(),
            colmap_runner=FakeColmap(),
        )
        result = worker.run(config)

        self.assertEqual(result.status, "completed")
        self.assertEqual(result.extracted_frame_count, 1)
        self.assertEqual(len(result.sparse_models), 1)
        self.assertEqual(result.registered_image_count, 1)
        self.assertEqual(result.sparse_point_count, 25)
        self.assertEqual(result.matcher_used, "exhaustive")

    def test_weak_sequential_reconstruction_retries_in_clean_workspace(self) -> None:
        config = self.config(matcher="sequential")

        class TenFrameExtractor:
            def extract(self, worker_config):
                frames = []
                for index in range(10):
                    frame = worker_config.images_directory / ("frame_%08d.jpg" % index)
                    frame.write_bytes(b"image")
                    frames.append(frame)
                return frames

        class ImprovingColmap:
            def __init__(self):
                self.calls = []

            def run(self, worker_config, matcher, log_prefix=""):
                if self.calls:
                    self_test.assertFalse(worker_config.database_path.exists())
                    self_test.assertEqual(list(worker_config.sparse_directory.iterdir()), [])
                self.calls.append((matcher, log_prefix))
                registered = 1 if matcher == "sequential" else 8
                worker_config.database_path.write_bytes(b"sqlite")
                model = worker_config.sparse_directory / "0"
                model.mkdir()
                (model / "cameras.bin").write_bytes(struct.pack("<Q", 1))
                (model / "images.bin").write_bytes(struct.pack("<Q", registered))
                (model / "points3D.bin").write_bytes(struct.pack("<Q", 120))

        self_test = self
        fake_colmap = ImprovingColmap()
        result = ColmapReconstructionWorker(
            frame_extractor=TenFrameExtractor(),
            colmap_runner=fake_colmap,
        ).run(config)

        self.assertEqual(
            fake_colmap.calls,
            [("sequential", ""), ("exhaustive", "retry-")],
        )
        self.assertTrue(result.retry_attempted)
        self.assertTrue(result.retry_succeeded)
        self.assertEqual(result.matcher_used, "exhaustive")
        self.assertEqual(result.registered_image_count, 8)

    def test_worker_refuses_to_overwrite_existing_job(self) -> None:
        config = self.config()
        config.job_directory.mkdir(parents=True)
        (config.job_directory / "keep.txt").write_text("keep", encoding="utf-8")

        with self.assertRaises(ReconstructionWorkspaceError):
            ColmapReconstructionWorker().run(config)


if __name__ == "__main__":
    unittest.main()
