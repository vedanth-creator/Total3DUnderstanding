# Local COLMAP reconstruction

This package extracts ordered frames from one room video with FFmpeg and runs
COLMAP's sparse reconstruction pipeline:

1. `feature_extractor`
2. `sequential_matcher`
3. `mapper`

It is a standalone local CLI. It is **not** connected to the FastAPI job
processor yet, does not replace the backend's normalized sample scene, and does
not run Nerfstudio, Total3D, dense reconstruction, or mesh generation.

## Prerequisites

Install FFmpeg and COLMAP separately and ensure their executables are on
`PATH`, or pass explicit paths with `--ffmpeg-binary` and `--colmap-binary`.

## Usage

Run from the repository root:

```bash
python -m reconstruction.scripts.run_colmap_job \
  --job-id example-room \
  --video /absolute/path/to/room.mov \
  --workspace-root "$PWD/reconstruction/jobs" \
  --frames-per-second 2 \
  --max-image-size 1600 \
  --matcher auto \
  --guided-matching \
  --cpu-only
```

`--workspace-root` is the complete parent directory for jobs. The worker
appends only the job ID. `--cpu-only` adds COLMAP 4.1.1's
`FeatureExtraction.use_gpu=0` and `FeatureMatching.use_gpu=0` settings.
Mapping itself does not use CUDA in this command sequence.

Matcher choices are `sequential`, `exhaustive`, and `auto`. Auto uses
exhaustive matching for 150 or fewer extracted frames and sequential matching
for larger jobs. If a sequential reconstruction registers less than the
configured minimum ratio (20% by default), the worker removes `database.db`
and `sparse/`, reruns feature extraction, exhaustive matching, and mapping, and
writes the retry to separate `retry-*.log` files.

COLMAP 4.1.1 mapper initialization can be tuned with:

- `--mapper-min-num-matches`
- `--mapper-init-min-num-inliers`
- `--mapper-init-max-error`
- `--mapper-init-min-tri-angle`
- `--mapper-init-max-forward-motion`
- `--minimum-registration-ratio`

The room-video defaults moderately relax initialization to 50 inliers and an
8-degree triangulation angle while retaining COLMAP's 4-pixel initialization
error threshold.

Each job uses a new, non-empty-safe directory:

```text
reconstruction/jobs/<job-id>/
  database.db
  reconstruction.json
  images/
    frame_00000000.jpg
    frame_00000001.jpg
  logs/
    ffmpeg-frame-extraction.log
    colmap-feature-extractor.log
    colmap-sequential-matcher.log
    colmap-mapper.log
    retry-colmap-feature-extractor.log
    retry-colmap-exhaustive-matcher.log
    retry-colmap-mapper.log
  sparse/
    0/
      cameras.bin
      images.bin
      points3D.bin
```

The CLI refuses to overwrite a non-empty job directory. If a subprocess fails,
the original error is raised, its log remains available, and
`reconstruction.json` records the failed status. Delete an obsolete job
explicitly or choose a new job ID before retrying.

`reconstruction.json` also records the strongest sparse model's registered
image and point counts, matcher used, retry outcome, total duration, failure
reason, and conservative capture recommendations when fewer than 20% of frames
register. Recommendations describe possible causes rather than claiming that
blur, texture, overlap, or parallax was directly measured.

## Prepare a Nerfstudio dataset

An existing sparse reconstruction can be converted into a portable dataset for
Nerfstudio without rerunning feature extraction, matching, or mapping:

```bash
python -m reconstruction.scripts.prepare_nerfstudio_job \
  --job-id <job-id> \
  --workspace-root reconstruction/jobs \
  --archive
```

The preparer ranks every sparse model by registered images and then sparse
points. It asks COLMAP `model_converter` for a temporary text export to obtain
the authoritative registered filenames and camera count; camera poses are not
parsed from binary data by this package. Only registered images are copied. The
selected binary model files are copied byte-for-byte to `colmap/sparse/0/`;
absolute source paths in the copied `project.ini` are normalized so they do not
refer to the original machine:

```text
reconstruction/jobs/<job-id>/nerfstudio-data/
  images/
  colmap/sparse/0/
  dataset-manifest.json
```

Options include `--model-id`, `--output-directory`, `--link-images`,
`--archive`, `--colmap-binary`, and `--force`. Image links are relative; when
an archive is requested, links are dereferenced so the tarball contains the
actual image bytes. Existing datasets and archives are never replaced without
`--force`.
