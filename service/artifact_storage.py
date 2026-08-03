"""Provider-neutral durable artifact storage."""

from abc import ABC, abstractmethod
import os
from pathlib import Path, PurePosixPath
import shutil
from typing import Any, Optional
from uuid import uuid4


class ArtifactStorageError(RuntimeError):
    pass


def validate_object_key(object_key: str) -> str:
    path = PurePosixPath(object_key)
    if not object_key or path.is_absolute() or ".." in path.parts or "" in path.parts:
        raise ArtifactStorageError("Unsafe object key.")
    return path.as_posix()


class ArtifactStorage(ABC):
    @abstractmethod
    def upload_file(self, local_path: Path, object_key: str) -> None: ...

    @abstractmethod
    def download_file(self, object_key: str, local_path: Path) -> None: ...

    @abstractmethod
    def create_download_url(self, object_key: str) -> str: ...

    @abstractmethod
    def create_upload_url(self, object_key: str) -> str: ...

    @abstractmethod
    def object_exists(self, object_key: str) -> bool: ...

    @abstractmethod
    def delete_object(self, object_key: str) -> None: ...


class LocalArtifactStorage(ArtifactStorage):
    def __init__(self, root: Path) -> None:
        self.root = root.expanduser().resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        destination = (self.root / validate_object_key(key)).resolve()
        if self.root not in destination.parents:
            raise ArtifactStorageError("Object key escapes storage root.")
        return destination

    def upload_file(self, local_path: Path, object_key: str) -> None:
        source = Path(local_path)
        if not source.is_file():
            raise ArtifactStorageError("Upload source does not exist: %s" % source)
        destination = self._path(object_key)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".tmp-" + uuid4().hex)
        shutil.copy2(source, temporary)
        os.replace(str(temporary), str(destination))

    def download_file(self, object_key: str, local_path: Path) -> None:
        source = self._path(object_key)
        if not source.is_file():
            raise ArtifactStorageError("Object does not exist: %s" % object_key)
        destination = Path(local_path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)

    def create_download_url(self, object_key: str) -> str:
        path = self._path(object_key)
        if not path.is_file():
            raise ArtifactStorageError("Object does not exist: %s" % object_key)
        return path.as_uri()

    def create_upload_url(self, object_key: str) -> str:
        return self._path(object_key).as_uri()

    def object_exists(self, object_key: str) -> bool:
        return self._path(object_key).is_file()

    def delete_object(self, object_key: str) -> None:
        path = self._path(object_key)
        if path.is_file():
            path.unlink()


class S3CompatibleArtifactStorage(ArtifactStorage):
    def __init__(self, client: Any, bucket: str, prefix: str = "", url_ttl: int = 3600) -> None:
        self.client = client
        self.bucket = bucket
        self.prefix = prefix.strip("/")
        self.url_ttl = url_ttl

    @classmethod
    def from_environment(cls, client: Optional[Any] = None) -> "S3CompatibleArtifactStorage":
        bucket = os.environ.get("ARTIFACT_S3_BUCKET")
        if not bucket:
            raise ArtifactStorageError("ARTIFACT_S3_BUCKET is required.")
        if client is None:
            try:
                import boto3  # type: ignore
            except ImportError as error:
                raise ArtifactStorageError("Install boto3 to use S3 storage.") from error
            client = boto3.client(
                "s3",
                endpoint_url=os.environ.get("ARTIFACT_S3_ENDPOINT_URL"),
                region_name=os.environ.get("ARTIFACT_S3_REGION"),
                aws_access_key_id=os.environ.get("ARTIFACT_S3_ACCESS_KEY_ID"),
                aws_secret_access_key=os.environ.get("ARTIFACT_S3_SECRET_ACCESS_KEY"),
            )
        return cls(client, bucket, os.environ.get("ARTIFACT_S3_PREFIX", ""))

    def _key(self, key: str) -> str:
        safe = validate_object_key(key)
        return "%s/%s" % (self.prefix, safe) if self.prefix else safe

    def upload_file(self, local_path: Path, object_key: str) -> None:
        self.client.upload_file(str(local_path), self.bucket, self._key(object_key))

    def download_file(self, object_key: str, local_path: Path) -> None:
        Path(local_path).parent.mkdir(parents=True, exist_ok=True)
        self.client.download_file(self.bucket, self._key(object_key), str(local_path))

    def create_download_url(self, object_key: str) -> str:
        return self.client.generate_presigned_url("get_object", Params={"Bucket": self.bucket, "Key": self._key(object_key)}, ExpiresIn=self.url_ttl)

    def create_upload_url(self, object_key: str) -> str:
        return self.client.generate_presigned_url("put_object", Params={"Bucket": self.bucket, "Key": self._key(object_key)}, ExpiresIn=self.url_ttl)

    def object_exists(self, object_key: str) -> bool:
        try:
            self.client.head_object(Bucket=self.bucket, Key=self._key(object_key))
            return True
        except Exception as error:
            response = getattr(error, "response", {})
            code = str(response.get("Error", {}).get("Code", ""))
            if code in {"404", "NoSuchKey", "NotFound"}:
                return False
            raise

    def delete_object(self, object_key: str) -> None:
        self.client.delete_object(Bucket=self.bucket, Key=self._key(object_key))
