"""Sparse COLMAP command construction and execution."""

from typing import List

from reconstruction.config import ReconstructionConfig
from reconstruction.process_runner import ProcessRunner


class ColmapRunner:
    def __init__(self, process_runner: ProcessRunner) -> None:
        self.process_runner = process_runner

    def run(
        self,
        config: ReconstructionConfig,
        matcher: str,
        log_prefix: str = "",
    ) -> None:
        if matcher not in {"sequential", "exhaustive"}:
            raise ValueError("Resolved matcher must be sequential or exhaustive.")
        self.run_feature_extractor(config, log_prefix=log_prefix)
        self.run_matcher(config, matcher=matcher, log_prefix=log_prefix)
        self.run_mapper(config, log_prefix=log_prefix)

    def run_feature_extractor(
        self,
        config: ReconstructionConfig,
        log_prefix: str = "",
    ) -> None:
        arguments = [
            config.colmap_binary,
            "feature_extractor",
            "--database_path",
            str(config.database_path),
            "--image_path",
            str(config.images_directory),
            "--ImageReader.single_camera",
            "1",
            "--ImageReader.camera_model",
            "SIMPLE_RADIAL",
            "--FeatureExtraction.max_image_size",
            str(config.max_image_size),
        ]
        if config.cpu_only:
            arguments.extend(["--FeatureExtraction.use_gpu", "0"])
        self.process_runner.run(
            arguments,
            log_path=config.logs_directory
            / (log_prefix + "colmap-feature-extractor.log"),
            cwd=config.job_directory,
        )

    def run_matcher(
        self,
        config: ReconstructionConfig,
        matcher: str,
        log_prefix: str = "",
    ) -> None:
        if matcher == "sequential":
            self.run_sequential_matcher(config, log_prefix=log_prefix)
        elif matcher == "exhaustive":
            self.run_exhaustive_matcher(config, log_prefix=log_prefix)
        else:
            raise ValueError("Resolved matcher must be sequential or exhaustive.")

    def run_sequential_matcher(
        self,
        config: ReconstructionConfig,
        log_prefix: str = "",
    ) -> None:
        arguments = [
            config.colmap_binary,
            "sequential_matcher",
            "--database_path",
            str(config.database_path),
        ]
        self._add_matching_options(arguments, config)
        self.process_runner.run(
            arguments,
            log_path=config.logs_directory
            / (log_prefix + "colmap-sequential-matcher.log"),
            cwd=config.job_directory,
        )

    def run_exhaustive_matcher(
        self,
        config: ReconstructionConfig,
        log_prefix: str = "",
    ) -> None:
        arguments = [
            config.colmap_binary,
            "exhaustive_matcher",
            "--database_path",
            str(config.database_path),
        ]
        self._add_matching_options(arguments, config)
        self.process_runner.run(
            arguments,
            log_path=config.logs_directory
            / (log_prefix + "colmap-exhaustive-matcher.log"),
            cwd=config.job_directory,
        )

    @staticmethod
    def _add_matching_options(
        arguments: List[str],
        config: ReconstructionConfig,
    ) -> None:
        if config.cpu_only:
            arguments.extend(["--FeatureMatching.use_gpu", "0"])
        if config.guided_matching:
            arguments.extend(["--FeatureMatching.guided_matching", "1"])

    def run_mapper(
        self,
        config: ReconstructionConfig,
        log_prefix: str = "",
    ) -> None:
        arguments = [
            config.colmap_binary,
            "mapper",
            "--database_path",
            str(config.database_path),
            "--image_path",
            str(config.images_directory),
            "--output_path",
            str(config.sparse_directory),
            "--Mapper.min_num_matches",
            str(config.mapper_min_num_matches),
            "--Mapper.init_min_num_inliers",
            str(config.mapper_init_min_num_inliers),
            "--Mapper.init_max_error",
            str(config.mapper_init_max_error),
            "--Mapper.init_min_tri_angle",
            str(config.mapper_init_min_tri_angle),
            "--Mapper.init_max_forward_motion",
            str(config.mapper_init_max_forward_motion),
        ]
        if config.cpu_only:
            arguments.extend(["--Mapper.ba_use_gpu", "0"])
        self.process_runner.run(
            arguments,
            log_path=config.logs_directory / (log_prefix + "colmap-mapper.log"),
            cwd=config.job_directory,
        )
