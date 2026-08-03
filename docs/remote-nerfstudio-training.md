# Automated remote Nerfstudio training

## Components

The API persists room-scan state as JSON, uploads the prepared dataset through
the `ArtifactStorage` interface, and submits a provider-neutral GPU request.
`RunPodGPUJobProvider` is the initial provider. The RunPod worker downloads the
dataset using a scoped URL, trains and exports without a viewer, and uploads
final artifacts using separate scoped PUT URLs. Permanent S3 and RunPod
credentials remain on backend/worker infrastructure and are never returned to
the iOS client.

The production processor is `RemoteTrainingReconstructionProcessor`. Configure
it in the application dependency wiring in place of `FakeReconstructionProcessor`;
the default fake processor and sample-scene fallback remain unchanged for local
development and existing clients.

## Backend environment

Required for RunPod and S3-compatible storage:

```text
RUNPOD_API_KEY
RUNPOD_ENDPOINT_ID
ARTIFACT_S3_BUCKET
ARTIFACT_S3_ENDPOINT_URL
ARTIFACT_S3_REGION
ARTIFACT_S3_ACCESS_KEY_ID
ARTIFACT_S3_SECRET_ACCESS_KEY
```

Optional:

```text
RUNPOD_API_BASE=https://api.runpod.ai/v2
ARTIFACT_S3_PREFIX=room-training
ROOM_SCAN_JOBS_DIRECTORY=storage/jobs
NERFSTUDIO_MAX_ITERATIONS=30000
GPU_JOB_STALE_SECONDS=28800
```

Install the backend additions with `python -m pip install -r
requirements-training.txt`. Local tests can use `LocalArtifactStorage`; it
returns `file:` URLs and requires no cloud account.

## Worker image and RunPod endpoint

Build from the repository root so the Docker build can copy both worker and
shared pinned requirements:

```bash
docker build -f gpu_worker/Dockerfile -t your-registry/room-scan-worker:1 .
docker push your-registry/room-scan-worker:1
```

Create a RunPod Serverless endpoint using that immutable image tag, an RTX 4090
worker, and enough persistent/container disk for the dataset plus two copies of
training output. Configure zero idle workers when minimizing cost, or one idle
worker when avoiding cold starts. RunPod billing continues while a worker is
starting or processing; successful, failed, timed-out, and cancelled jobs must
all be allowed to terminate so the worker is released.

The image contains CUDA 11.8, GCC/G++ 11, PyTorch 2.1.2, Nerfstudio 1.1.5, and
gsplat 1.4.0. It installs nothing at job time and never uses an unsupported
compiler override.

## Submission and status lifecycle

After `NerfstudioDatasetPreparer` creates `nerfstudio-data.tar.gz`, call:

```python
orchestrator.submit_prepared_dataset(room_scan_id, archive_path)
```

The production reconstruction processor performs this handoff automatically.
Submission is idempotent once `provider_job_id` is persisted. Stable artifact
keys are scoped beneath `room-scans/<room-scan-id>/`; retries overwrite only
that scan's expected keys.

Run durable reconciliation from cron, systemd, Kubernetes CronJob, or a queue
scheduler. FastAPI also performs a startup reconciliation, but correctness does
not depend on that in-memory lifecycle:

```bash
python -m service.scripts.reconcile_training_jobs
```

Suggested interval is 15–30 seconds for active jobs. Completion is persisted
only after the splat, archive, log, and result manifest all exist. Duplicate
poll results are idempotent. Jobs beyond `GPU_JOB_STALE_SECONDS` fail with an
infrastructure reason.

## Test scan and API operations

Submit using the existing multipart endpoint:

```bash
curl -F 'video=@room.mov;type=video/quicktime' \
  http://localhost:8000/v1/room-scans
```

Inspect status without changing the existing contract:

```bash
curl http://localhost:8000/v1/room-scans/<room-scan-id>
```

The additive `training` object reports stage, progress, artifact availability,
viewer readiness, and client-safe failure details. Download endpoints issue
short-lived redirects:

```text
GET /v1/room-scans/<id>/artifacts/splat
GET /v1/room-scans/<id>/artifacts/training_archive
GET /v1/room-scans/<id>/artifacts/logs
```

Cancel queued or active work with:

```bash
curl -X POST http://localhost:8000/v1/room-scans/<id>/cancel
```

## Artifact layout

```text
room-scans/<id>/
  inputs/nerfstudio-data.tar.gz
  logs/training.log
  outputs/splat.ply
  outputs/nerfstudio-training.tar.gz
  outputs/result.json
```

## Failure and recovery

`invalid_dataset`, `training_failure`, and `infrastructure_failure` are stored
separately. Worker logs and failure manifests are uploaded on a best-effort
basis. Interrupted local COLMAP workspaces are moved to a hidden recovery
directory before a clean retry, preserving their logs. If submission succeeded
but the API restarted before polling, the persisted provider ID lets the
reconciler resume. If RunPod completed before object storage became consistent,
the job remains in `uploading_artifacts` and is checked again. Cancel stale jobs
before resubmitting; stable per-scan keys prevent conflicting final artifacts.

Never put permanent credentials in job payloads, logs, the iOS application, or
Docker images. Rotate a leaked key at the provider and invalidate outstanding
signed URLs by reducing their expiration or changing the object prefix.
