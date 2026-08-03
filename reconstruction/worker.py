"""Synchronous orchestration for one local sparse reconstruction job."""

import shutil
import time
from typing import Optional

from reconstruction.colmap_runner import ColmapRunner
from reconstruction.config import ReconstructionConfig
from reconstruction.frame_extractor import FrameExtractor
from reconstruction.models import ReconstructionResult
from reconstruction.process_runner import ProcessRunner
from reconstruction.result_parser import ReconstructionResultParser


class ReconstructionWorkspaceError(RuntimeError):
    pass


class ColmapReconstructionWorker:
    def __init__(
        self,
        frame_extractor: Optional[FrameExtractor] = None,
        colmap_runner: Optional[ColmapRunner] = None,
        result_parser: Optional[ReconstructionResultParser] = None,
    ) -> None:
        process_runner = ProcessRunner()
        self.frame_extractor = frame_extractor or FrameExtractor(process_runner)
        self.colmap_runner = colmap_runner or ColmapRunner(process_runner)
        self.result_parser = result_parser or ReconstructionResultParser()

    def run(self, config: ReconstructionConfig) -> ReconstructionResult:
        if config.job_directory.exists() and any(config.job_directory.iterdir()):
            raise ReconstructionWorkspaceError(
                "Job workspace already contains artifacts: %s. Use a new job ID "
                "or remove the old job explicitly." % config.job_directory
            )

        config.prepare_directories()
        extracted_frame_count = 0
        matcher_used = None
        retry_attempted = False
        retry_succeeded = False
        started_at = time.monotonic()
        try:
            frames = self.frame_extractor.extract(config)
            extracted_frame_count = len(frames)
            matcher_used = config.matcher_for_frame_count(extracted_frame_count)
            self.colmap_runner.run(config, matcher=matcher_used)

            initial_models = self.result_parser.summarize_models(
                config.sparse_directory
            )
            initial_registered, _ = self.result_parser.strongest_model_counts(
                initial_models
            )
            if matcher_used == "sequential" and self._registration_is_poor(
                initial_registered,
                extracted_frame_count,
                config.minimum_registration_ratio,
            ):
                retry_attempted = True
                self._reset_colmap_artifacts(config)
                matcher_used = "exhaustive"
                self.colmap_runner.run(
                    config,
                    matcher=matcher_used,
                    log_prefix="retry-",
                )
                retry_models = self.result_parser.summarize_models(
                    config.sparse_directory
                )
                retry_registered, _ = self.result_parser.strongest_model_counts(
                    retry_models
                )
                retry_succeeded = not self._registration_is_poor(
                    retry_registered,
                    extracted_frame_count,
                    config.minimum_registration_ratio,
                )

            return self.result_parser.parse(
                config,
                extracted_frame_count,
                matcher_used=matcher_used,
                retry_attempted=retry_attempted,
                retry_succeeded=retry_succeeded,
                reconstruction_duration_seconds=time.monotonic() - started_at,
            )
        except Exception as error:
            self.result_parser.write_failure(
                config,
                extracted_frame_count=extracted_frame_count,
                error=str(error),
                matcher_used=matcher_used,
                retry_attempted=retry_attempted,
                retry_succeeded=retry_succeeded,
                reconstruction_duration_seconds=time.monotonic() - started_at,
            )
            raise

    @staticmethod
    def _registration_is_poor(
        registered_image_count: int,
        extracted_frame_count: int,
        minimum_registration_ratio: float,
    ) -> bool:
        if extracted_frame_count <= 0:
            return True
        return registered_image_count / extracted_frame_count < minimum_registration_ratio

    @staticmethod
    def _reset_colmap_artifacts(config: ReconstructionConfig) -> None:
        # The retry preserves extracted images and first-attempt logs, but uses
        # a brand-new database and sparse directory so no stale feature or
        # matching state is reused.
        if config.database_path.exists():
            config.database_path.unlink()
        if config.sparse_directory.exists():
            shutil.rmtree(config.sparse_directory)
        config.sparse_directory.mkdir(parents=False, exist_ok=False)
