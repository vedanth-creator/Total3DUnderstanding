"""Prepare a portable Nerfstudio dataset from an existing COLMAP job."""

import argparse
from pathlib import Path
import sys
from typing import Optional, Sequence

from reconstruction.nerfstudio_dataset import (
    NerfstudioDatasetError,
    NerfstudioDatasetPreparer,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Select the strongest COLMAP sparse model and prepare a filtered, "
            "portable Nerfstudio dataset without rerunning reconstruction."
        )
    )
    parser.add_argument("--job-id", required=True, help="Existing reconstruction job ID.")
    parser.add_argument(
        "--workspace-root",
        required=True,
        type=Path,
        help="Complete directory containing reconstruction job folders.",
    )
    parser.add_argument(
        "--output-directory",
        type=Path,
        help="Dataset destination (default: <job>/nerfstudio-data).",
    )
    parser.add_argument(
        "--model-id",
        help="Specific sparse model ID; strongest model is selected when omitted.",
    )
    parser.add_argument(
        "--link-images",
        action="store_true",
        help="Create relative image symlinks instead of copying image bytes.",
    )
    parser.add_argument(
        "--archive",
        action="store_true",
        help="Create <job>/nerfstudio-data.tar.gz with dereferenced image bytes.",
    )
    parser.add_argument(
        "--colmap-binary",
        default="colmap",
        help=(
            "Retained for CLI compatibility; preparation now reads the selected "
            "COLMAP binary model directly and does not invoke this executable."
        ),
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace an existing dataset and requested archive.",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    arguments = build_parser().parse_args(argv)
    try:
        prepared = NerfstudioDatasetPreparer().prepare(
            job_id=arguments.job_id,
            workspace_root=arguments.workspace_root,
            output_directory=arguments.output_directory,
            model_id=arguments.model_id,
            link_images=arguments.link_images,
            archive=arguments.archive,
            colmap_binary=arguments.colmap_binary,
            force=arguments.force,
        )
    except (NerfstudioDatasetError, OSError, ValueError) as error:
        print("Nerfstudio dataset preparation failed: %s" % error, file=sys.stderr)
        return 1

    manifest = prepared.manifest
    print("Nerfstudio dataset prepared: %s" % prepared.dataset_directory)
    print("Selected sparse model: %s" % manifest.selected_sparse_model_id)
    print("Registered images: %d" % manifest.registered_image_count)
    if prepared.archive_path is not None:
        print("Archive: %s" % prepared.archive_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
