"""Summarize sparse COLMAP artifacts into reconstruction.json."""

from pathlib import Path
import struct
from typing import List, Optional

from reconstruction.config import ReconstructionConfig
from reconstruction.models import ReconstructionResult, SparseModelSummary


class ReconstructionResultError(RuntimeError):
    pass


class ReconstructionResultParser:
    def parse(
        self,
        config: ReconstructionConfig,
        extracted_frame_count: int,
        matcher_used: str,
        retry_attempted: bool = False,
        retry_succeeded: bool = False,
        reconstruction_duration_seconds: float = 0.0,
    ) -> ReconstructionResult:
        models = self.summarize_models(config.sparse_directory)
        if not models:
            raise ReconstructionResultError(
                "COLMAP mapper completed but produced no sparse model under %s."
                % config.sparse_directory
            )
        if not config.database_path.is_file():
            raise ReconstructionResultError(
                "COLMAP did not produce the expected database: %s"
                % config.database_path
            )

        registered_image_count, sparse_point_count = self.strongest_model_counts(models)
        result = self._make_result(
            config=config,
            status="completed",
            extracted_frame_count=extracted_frame_count,
            sparse_models=models,
            registered_image_count=registered_image_count,
            sparse_point_count=sparse_point_count,
            matcher_used=matcher_used,
            retry_attempted=retry_attempted,
            retry_succeeded=retry_succeeded,
            reconstruction_duration_seconds=reconstruction_duration_seconds,
            error=None,
            failure_reason=None,
            recommendations=self.recommendations_for_quality(
                extracted_frame_count,
                registered_image_count,
                config.minimum_registration_ratio,
            ),
        )
        result.write_json(config.result_path)
        return result

    def write_failure(
        self,
        config: ReconstructionConfig,
        extracted_frame_count: int,
        error: str,
        matcher_used: Optional[str] = None,
        retry_attempted: bool = False,
        retry_succeeded: bool = False,
        reconstruction_duration_seconds: float = 0.0,
    ) -> ReconstructionResult:
        models = self.summarize_models(config.sparse_directory)
        registered_image_count, sparse_point_count = self.strongest_model_counts(models)
        result = self._make_result(
            config=config,
            status="failed",
            extracted_frame_count=extracted_frame_count,
            sparse_models=models,
            registered_image_count=registered_image_count,
            sparse_point_count=sparse_point_count,
            matcher_used=matcher_used,
            retry_attempted=retry_attempted,
            retry_succeeded=retry_succeeded,
            reconstruction_duration_seconds=reconstruction_duration_seconds,
            error=error,
            failure_reason=error,
            recommendations=self.recommendations_for_quality(
                extracted_frame_count,
                registered_image_count,
                config.minimum_registration_ratio,
            ),
        )
        result.write_json(config.result_path)
        return result

    def _make_result(
        self,
        config: ReconstructionConfig,
        status: str,
        extracted_frame_count: int,
        sparse_models: List[SparseModelSummary],
        registered_image_count: int,
        sparse_point_count: int,
        matcher_used: Optional[str],
        retry_attempted: bool,
        retry_succeeded: bool,
        reconstruction_duration_seconds: float,
        error: Optional[str],
        failure_reason: Optional[str],
        recommendations: List[str],
    ) -> ReconstructionResult:
        return ReconstructionResult(
            job_id=config.job_id,
            status=status,
            video_path=str(config.video_path),
            job_directory=str(config.job_directory),
            images_directory=str(config.images_directory),
            database_path=str(config.database_path),
            sparse_directory=str(config.sparse_directory),
            logs_directory=str(config.logs_directory),
            extracted_frame_count=extracted_frame_count,
            registered_image_count=registered_image_count,
            sparse_point_count=sparse_point_count,
            matcher_used=matcher_used,
            retry_attempted=retry_attempted,
            retry_succeeded=retry_succeeded,
            reconstruction_duration_seconds=reconstruction_duration_seconds,
            sparse_models=sparse_models,
            error=error,
            failure_reason=failure_reason,
            recommendations=recommendations,
        )

    def summarize_models(self, sparse_directory: Path) -> List[SparseModelSummary]:
        if not sparse_directory.is_dir():
            return []
        summaries: List[SparseModelSummary] = []
        for candidate in sorted(sparse_directory.iterdir(), key=lambda path: path.name):
            if not candidate.is_dir() or not self._looks_like_model(candidate):
                continue
            summaries.append(
                SparseModelSummary(
                    model_id=candidate.name,
                    path=str(candidate),
                    registered_image_count=self._read_registered_image_count(candidate),
                    sparse_point_count=self._read_sparse_point_count(candidate),
                )
            )
        return summaries

    @staticmethod
    def strongest_model_counts(
        models: List[SparseModelSummary],
    ) -> tuple:
        if not models:
            return (0, 0)
        strongest = max(
            models,
            key=lambda model: (
                model.registered_image_count or 0,
                model.sparse_point_count or 0,
            ),
        )
        return (
            strongest.registered_image_count or 0,
            strongest.sparse_point_count or 0,
        )

    @staticmethod
    def recommendations_for_quality(
        extracted_frame_count: int,
        registered_image_count: int,
        minimum_registration_ratio: float = 0.20,
    ) -> List[str]:
        if extracted_frame_count <= 0:
            return ["Verify that FFmpeg can decode usable frames from the video."]
        if registered_image_count / extracted_frame_count >= minimum_registration_ratio:
            return []
        return [
            "Possible cause: insufficient parallax between views.",
            "Possible cause: excessive motion blur or too few textured surfaces.",
            "Capture more overlap between neighboring views.",
            "Record with slower sideways movement instead of mostly forward motion.",
        ]

    @staticmethod
    def _looks_like_model(model_directory: Path) -> bool:
        return all(
            (model_directory / (stem + ".bin")).is_file()
            or (model_directory / (stem + ".txt")).is_file()
            for stem in ("cameras", "images", "points3D")
        )

    @staticmethod
    def _read_registered_image_count(model_directory: Path) -> Optional[int]:
        images_binary = model_directory / "images.bin"
        if images_binary.is_file():
            return ReconstructionResultParser._read_binary_count(images_binary)
        images_text = model_directory / "images.txt"
        if not images_text.is_file():
            return None
        # COLMAP's text format uses two lines per registered image: image
        # metadata followed by its POINTS2D observations. The observation line
        # may be empty, so it must not be discarded during counting.
        count = 0
        expecting_metadata = True
        for line in images_text.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("#"):
                continue
            if expecting_metadata:
                if not line.strip():
                    continue
                count += 1
                expecting_metadata = False
            else:
                expecting_metadata = True
        return count

    @staticmethod
    def _read_sparse_point_count(model_directory: Path) -> Optional[int]:
        points_binary = model_directory / "points3D.bin"
        if points_binary.is_file():
            return ReconstructionResultParser._read_binary_count(points_binary)
        points_text = model_directory / "points3D.txt"
        if not points_text.is_file():
            return None
        return sum(
            1
            for line in points_text.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        )

    @staticmethod
    def _read_binary_count(path: Path) -> int:
        with path.open("rb") as handle:
            header = handle.read(8)
        if len(header) != 8:
            raise ReconstructionResultError(
                "COLMAP model file has an incomplete count header: %s" % path
            )
        return int(struct.unpack("<Q", header)[0])
