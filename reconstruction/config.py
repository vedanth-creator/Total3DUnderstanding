"""Validated filesystem and process configuration for a COLMAP job."""

from dataclasses import dataclass
from pathlib import Path
import re


_SAFE_JOB_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


@dataclass(frozen=True)
class ReconstructionConfig:
    job_id: str
    video_path: Path
    workspace_root: Path
    frames_per_second: float = 2.0
    max_image_size: int = 1600
    matcher: str = "auto"
    guided_matching: bool = False
    mapper_min_num_matches: int = 15
    mapper_init_min_num_inliers: int = 50
    mapper_init_max_error: float = 4.0
    mapper_init_min_tri_angle: float = 8.0
    mapper_init_max_forward_motion: float = 0.97
    minimum_registration_ratio: float = 0.20
    cpu_only: bool = False
    colmap_binary: str = "colmap"
    ffmpeg_binary: str = "ffmpeg"

    def __post_init__(self) -> None:
        if not _SAFE_JOB_ID.fullmatch(self.job_id) or self.job_id in {".", ".."}:
            raise ValueError(
                "job_id must contain only letters, numbers, dots, underscores, "
                "or hyphens and must not be a traversal path."
            )
        if self.frames_per_second <= 0:
            raise ValueError("frames_per_second must be greater than zero.")
        if self.max_image_size <= 0:
            raise ValueError("max_image_size must be greater than zero.")
        if self.matcher not in {"auto", "sequential", "exhaustive"}:
            raise ValueError("matcher must be auto, sequential, or exhaustive.")
        if self.mapper_min_num_matches <= 0:
            raise ValueError("mapper_min_num_matches must be greater than zero.")
        if self.mapper_init_min_num_inliers <= 0:
            raise ValueError("mapper_init_min_num_inliers must be greater than zero.")
        if self.mapper_init_max_error <= 0:
            raise ValueError("mapper_init_max_error must be greater than zero.")
        if self.mapper_init_min_tri_angle <= 0:
            raise ValueError("mapper_init_min_tri_angle must be greater than zero.")
        if not 0 < self.mapper_init_max_forward_motion <= 1:
            raise ValueError(
                "mapper_init_max_forward_motion must be greater than zero and at most one."
            )
        if not 0 < self.minimum_registration_ratio <= 1:
            raise ValueError(
                "minimum_registration_ratio must be greater than zero and at most one."
            )
        if not self.colmap_binary.strip():
            raise ValueError("colmap_binary must not be empty.")
        if not self.ffmpeg_binary.strip():
            raise ValueError("ffmpeg_binary must not be empty.")

        object.__setattr__(self, "video_path", Path(self.video_path).expanduser().resolve())
        object.__setattr__(
            self,
            "workspace_root",
            Path(self.workspace_root).expanduser().resolve(),
        )

    @property
    def jobs_root(self) -> Path:
        return self.workspace_root

    @property
    def job_directory(self) -> Path:
        # workspace_root is canonicalized once in __post_init__; the safe job
        # identifier is then appended directly without adding path segments.
        destination = self.jobs_root / self.job_id
        if destination.parent != self.jobs_root:
            raise ValueError("Resolved job directory escapes the jobs root.")
        return destination

    @property
    def images_directory(self) -> Path:
        return self.job_directory / "images"

    @property
    def logs_directory(self) -> Path:
        return self.job_directory / "logs"

    @property
    def sparse_directory(self) -> Path:
        return self.job_directory / "sparse"

    @property
    def database_path(self) -> Path:
        return self.job_directory / "database.db"

    @property
    def result_path(self) -> Path:
        return self.job_directory / "reconstruction.json"

    def prepare_directories(self) -> None:
        self.images_directory.mkdir(parents=True, exist_ok=False)
        self.logs_directory.mkdir(parents=False, exist_ok=False)
        self.sparse_directory.mkdir(parents=False, exist_ok=False)

    def matcher_for_frame_count(self, extracted_frame_count: int) -> str:
        if extracted_frame_count < 0:
            raise ValueError("extracted_frame_count must not be negative.")
        if self.matcher == "auto":
            return "exhaustive" if extracted_frame_count <= 150 else "sequential"
        return self.matcher
