"""Bounded, streaming local storage for uploaded room videos."""

from dataclasses import dataclass
from pathlib import Path
import shutil
from typing import Mapping
from uuid import UUID

from fastapi import UploadFile


class UploadValidationError(ValueError):
    pass


class UploadTooLargeError(UploadValidationError):
    pass


@dataclass(frozen=True)
class StoredUpload:
    absolute_path: Path
    relative_path: str
    size_bytes: int
    extension: str


class LocalUploadStorage:
    ALLOWED_TYPES: Mapping[str, frozenset] = {
        ".mov": frozenset(("video/quicktime", "video/mov")),
        ".mp4": frozenset(("video/mp4",)),
        ".m4v": frozenset(("video/x-m4v", "video/mp4")),
    }

    def __init__(
        self,
        storage_root: Path,
        maximum_upload_bytes: int = 500 * 1024 * 1024,
        chunk_size: int = 1024 * 1024,
    ) -> None:
        if maximum_upload_bytes <= 0 or chunk_size <= 0:
            raise ValueError("Upload size and chunk size must be positive.")
        self.storage_root = storage_root.resolve()
        self.uploads_directory = (self.storage_root / "uploads").resolve()
        self.uploads_directory.mkdir(parents=True, exist_ok=True)
        self.maximum_upload_bytes = maximum_upload_bytes
        self.chunk_size = chunk_size

    async def save(self, job_id: str, upload: UploadFile) -> StoredUpload:
        canonical = str(UUID(job_id))
        if canonical != job_id.lower():
            raise UploadValidationError("Invalid room-scan job ID.")

        extension = Path(upload.filename or "").suffix.lower()
        if extension not in self.ALLOWED_TYPES:
            raise UploadValidationError("Unsupported video extension.")
        content_type = (upload.content_type or "").lower()
        if content_type not in self.ALLOWED_TYPES[extension]:
            raise UploadValidationError("Unsupported video content type.")

        job_directory = (self.uploads_directory / canonical).resolve()
        if job_directory.parent != self.uploads_directory:
            raise UploadValidationError("Invalid upload path.")
        job_directory.mkdir(parents=False, exist_ok=False)
        destination = (job_directory / ("room-video" + extension)).resolve()
        if destination.parent != job_directory:
            raise UploadValidationError("Invalid upload destination.")

        total = 0
        try:
            with destination.open("xb") as output:
                while True:
                    chunk = await upload.read(self.chunk_size)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > self.maximum_upload_bytes:
                        raise UploadTooLargeError(
                            "Video exceeds the maximum upload size of %d bytes."
                            % self.maximum_upload_bytes
                        )
                    output.write(chunk)
            if total == 0:
                raise UploadValidationError("Uploaded video must not be empty.")
        except Exception:
            shutil.rmtree(job_directory, ignore_errors=True)
            raise
        finally:
            await upload.close()

        return StoredUpload(
            absolute_path=destination,
            relative_path=destination.relative_to(self.storage_root).as_posix(),
            size_bytes=total,
            extension=extension,
        )

    def delete_job_upload(self, job_id: str) -> None:
        canonical = str(UUID(job_id))
        if canonical != job_id.lower():
            raise UploadValidationError("Invalid room-scan job ID.")
        directory = (self.uploads_directory / canonical).resolve()
        if directory.parent != self.uploads_directory:
            raise UploadValidationError("Invalid upload path.")
        shutil.rmtree(directory, ignore_errors=True)
