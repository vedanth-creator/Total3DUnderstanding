"""Explicit cleanup helpers; active jobs are never deleted automatically."""

from service.job_repository import FileJobRepository
from service.upload_storage import LocalUploadStorage


def delete_room_scan_job(
    job_id: str,
    repository: FileJobRepository,
    upload_storage: LocalUploadStorage,
) -> None:
    upload_storage.delete_job_upload(job_id)
    repository.delete(job_id)
