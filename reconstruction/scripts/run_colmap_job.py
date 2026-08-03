"""Run one FFmpeg-to-COLMAP sparse reconstruction job."""

import argparse
from pathlib import Path
import sys
from typing import Optional, Sequence

from reconstruction.config import ReconstructionConfig
from reconstruction.worker import ColmapReconstructionWorker


def _positive_float(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a number") from error
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def _positive_integer(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be an integer") from error
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def _unit_ratio(value: str) -> float:
    parsed = _positive_float(value)
    if parsed > 1:
        raise argparse.ArgumentTypeError("must be at most one")
    return parsed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Extract ordered frames from a room video and build a sparse "
            "COLMAP reconstruction."
        )
    )
    parser.add_argument("--job-id", required=True, help="Safe identifier for this job.")
    parser.add_argument(
        "--video",
        required=True,
        type=Path,
        help="Path to the input MOV, MP4, or M4V video.",
    )
    parser.add_argument(
        "--workspace-root",
        required=True,
        type=Path,
        help="Complete parent directory under which <job-id>/ is created.",
    )
    parser.add_argument(
        "--frames-per-second",
        type=_positive_float,
        default=2.0,
        help="Frame extraction rate (default: 2.0).",
    )
    parser.add_argument(
        "--max-image-size",
        type=_positive_integer,
        default=1600,
        help="Maximum extracted image dimension and COLMAP SIFT size (default: 1600).",
    )
    parser.add_argument(
        "--matcher",
        choices=("auto", "sequential", "exhaustive"),
        default="auto",
        help=(
            "Matching strategy. Auto uses exhaustive for at most 150 frames "
            "and sequential otherwise (default: auto)."
        ),
    )
    parser.add_argument(
        "--guided-matching",
        action="store_true",
        help="Enable COLMAP 4.1.1 FeatureMatching.guided_matching.",
    )
    parser.add_argument(
        "--mapper-min-num-matches",
        type=_positive_integer,
        default=15,
        help="Mapper.min_num_matches (default: 15).",
    )
    parser.add_argument(
        "--mapper-init-min-num-inliers",
        type=_positive_integer,
        default=50,
        help="Mapper.init_min_num_inliers (default: 50).",
    )
    parser.add_argument(
        "--mapper-init-max-error",
        type=_positive_float,
        default=4.0,
        help="Mapper.init_max_error in pixels (default: 4.0).",
    )
    parser.add_argument(
        "--mapper-init-min-tri-angle",
        type=_positive_float,
        default=8.0,
        help="Mapper.init_min_tri_angle in degrees (default: 8.0).",
    )
    parser.add_argument(
        "--mapper-init-max-forward-motion",
        type=_unit_ratio,
        default=0.97,
        help="Mapper.init_max_forward_motion ratio (default: 0.97).",
    )
    parser.add_argument(
        "--minimum-registration-ratio",
        type=_unit_ratio,
        default=0.20,
        help="Sequential-to-exhaustive retry threshold (default: 0.20).",
    )
    parser.add_argument(
        "--cpu-only",
        action="store_true",
        help="Disable GPU use for COLMAP feature extraction and matching.",
    )
    parser.add_argument(
        "--colmap-binary",
        default="colmap",
        help="COLMAP executable name or path (default: colmap).",
    )
    parser.add_argument(
        "--ffmpeg-binary",
        default="ffmpeg",
        help="FFmpeg executable name or path (default: ffmpeg).",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    try:
        config = ReconstructionConfig(
            job_id=arguments.job_id,
            video_path=arguments.video,
            workspace_root=arguments.workspace_root,
            frames_per_second=arguments.frames_per_second,
            max_image_size=arguments.max_image_size,
            matcher=arguments.matcher,
            guided_matching=arguments.guided_matching,
            mapper_min_num_matches=arguments.mapper_min_num_matches,
            mapper_init_min_num_inliers=arguments.mapper_init_min_num_inliers,
            mapper_init_max_error=arguments.mapper_init_max_error,
            mapper_init_min_tri_angle=arguments.mapper_init_min_tri_angle,
            mapper_init_max_forward_motion=arguments.mapper_init_max_forward_motion,
            minimum_registration_ratio=arguments.minimum_registration_ratio,
            cpu_only=arguments.cpu_only,
            colmap_binary=arguments.colmap_binary,
            ffmpeg_binary=arguments.ffmpeg_binary,
        )
        result = ColmapReconstructionWorker().run(config)
    except (OSError, RuntimeError, ValueError) as error:
        print("COLMAP reconstruction failed: %s" % error, file=sys.stderr)
        return 1

    print("COLMAP reconstruction completed: %s" % config.result_path)
    print("Sparse models: %d" % len(result.sparse_models))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
