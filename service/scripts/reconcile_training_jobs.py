"""One-shot durable GPU status reconciliation, suitable for cron/systemd."""

import os
from pathlib import Path

from service.artifact_storage import S3CompatibleArtifactStorage
from service.gpu_jobs import RunPodGPUJobProvider
from service.job_repository import FileJobRepository
from service.training_orchestrator import TrainingOrchestrator


def main() -> int:
    jobs = Path(os.environ.get("ROOM_SCAN_JOBS_DIRECTORY", "storage/jobs"))
    orchestrator = TrainingOrchestrator(
        FileJobRepository(jobs),
        S3CompatibleArtifactStorage.from_environment(),
        RunPodGPUJobProvider.from_environment(),
        maximum_iterations=int(os.environ.get("NERFSTUDIO_MAX_ITERATIONS", "30000")),
        stale_after_seconds=int(os.environ.get("GPU_JOB_STALE_SECONDS", "28800")),
    )
    orchestrator.reconcile_once()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
