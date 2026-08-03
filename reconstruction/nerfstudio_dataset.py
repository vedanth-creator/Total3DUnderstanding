"""Prepare a portable Nerfstudio dataset from an existing COLMAP job."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import tempfile
from typing import Any, Dict, List, Optional, Sequence, Tuple
from uuid import uuid4

from reconstruction.models import SparseModelSummary
from reconstruction.process_runner import ProcessRunner, ProcessRunnerError
from reconstruction.result_parser import ReconstructionResultParser


_SAFE_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_REQUIRED_MODEL_FILES = ("cameras.bin", "images.bin", "points3D.bin")
_IMAGE_SUFFIXES = frozenset((".jpg", ".jpeg", ".png"))


class NerfstudioDatasetError(RuntimeError):
    """Base exception for dataset preparation failures."""


class UnsafeDatasetPathError(NerfstudioDatasetError):
    pass


class SparseModelNotFoundError(NerfstudioDatasetError):
    pass


class RegisteredImageMissingError(NerfstudioDatasetError):
    def __init__(self, missing_images: Sequence[str]) -> None:
        self.missing_images = tuple(missing_images)
        super().__init__(
            "COLMAP references missing extracted images: %s"
            % ", ".join(self.missing_images)
        )


class DatasetOverwriteError(NerfstudioDatasetError):
    pass


class DatasetValidationError(NerfstudioDatasetError):
    pass


class ModelConversionError(NerfstudioDatasetError):
    pass


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class NerfstudioDatasetManifest:
    job_id: str
    source_job_directory: str
    selected_sparse_model_id: str
    selected_sparse_model_path: str
    extracted_frame_count: int
    registered_image_count: int
    copied_image_count: int
    sparse_point_count: Optional[int]
    camera_count: int
    missing_images: List[str]
    dataset_directory: str
    warnings: List[str] = field(default_factory=list)
    created_at: str = field(default_factory=utc_now_iso)
    schema_version: str = "1.0"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "job_id": self.job_id,
            "source_job_directory": self.source_job_directory,
            "selected_sparse_model_id": self.selected_sparse_model_id,
            "selected_sparse_model_path": self.selected_sparse_model_path,
            "extracted_frame_count": self.extracted_frame_count,
            "registered_image_count": self.registered_image_count,
            "copied_image_count": self.copied_image_count,
            "sparse_point_count": self.sparse_point_count,
            "camera_count": self.camera_count,
            "missing_images": list(self.missing_images),
            "dataset_directory": self.dataset_directory,
            "created_at": self.created_at,
            "warnings": list(self.warnings),
        }

    def write_json(self, destination: Path) -> None:
        temporary = destination.with_suffix(destination.suffix + ".tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(self.to_dict(), handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))


@dataclass(frozen=True)
class PreparedNerfstudioDataset:
    dataset_directory: Path
    manifest: NerfstudioDatasetManifest
    archive_path: Optional[Path] = None


class NerfstudioDatasetPreparer:
    def __init__(self, process_runner: Optional[ProcessRunner] = None) -> None:
        self.process_runner = process_runner or ProcessRunner()
        self.model_parser = ReconstructionResultParser()

    def prepare(
        self,
        job_id: str,
        workspace_root: Path,
        output_directory: Optional[Path] = None,
        model_id: Optional[str] = None,
        link_images: bool = False,
        archive: bool = False,
        colmap_binary: str = "colmap",
        force: bool = False,
    ) -> PreparedNerfstudioDataset:
        safe_job_id = self._safe_identifier(job_id, "job ID")
        jobs_root = Path(workspace_root).expanduser().resolve()
        job_directory = jobs_root / safe_job_id
        if job_directory.parent != jobs_root or not job_directory.is_dir():
            raise UnsafeDatasetPathError(
                "Reconstruction job directory does not exist: %s" % job_directory
            )

        images_directory = job_directory / "images"
        sparse_directory = job_directory / "sparse"
        if not images_directory.is_dir():
            raise DatasetValidationError(
                "Extracted images directory is missing: %s" % images_directory
            )

        destination = self._resolve_output_directory(
            output_directory,
            job_directory,
        )
        archive_path = job_directory / "nerfstudio-data.tar.gz"
        self._check_overwrite(destination, archive_path, archive, force)

        selected_model = self.select_best_model(
            sparse_directory,
            requested_model_id=model_id,
        )
        selected_path = Path(selected_model.path).resolve()
        log_path = job_directory / "logs" / "nerfstudio-model-converter.log"

        staging = destination.parent / (
            ".%s.tmp-%s" % (destination.name, uuid4().hex)
        )
        try:
            staging.mkdir(parents=True, exist_ok=False)
            staging_images = staging / "images"
            staging_model = staging / "colmap" / "sparse" / "0"
            staging_images.mkdir(parents=True)
            staging_model.mkdir(parents=True)

            with tempfile.TemporaryDirectory(
                prefix="nerfstudio-model-text-",
                dir=str(job_directory),
            ) as temporary_text_directory:
                text_model = Path(temporary_text_directory)
                self._export_text_model_if_needed(
                    selected_path,
                    text_model,
                    colmap_binary,
                    log_path,
                )
                registered_names = self._read_registered_image_names(
                    text_model / "images.txt"
                )
                camera_count = self._count_text_records(text_model / "cameras.txt")

            if not registered_names:
                raise DatasetValidationError(
                    "Selected sparse model contains no registered images."
                )
            self._validate_registered_sources(images_directory, registered_names)
            self._copy_registered_images(
                images_directory,
                staging_images,
                registered_names,
                link_images,
            )
            project_ini_normalized = self._copy_model(selected_path, staging_model)

            extracted_frame_count = self._count_extracted_images(images_directory)
            warnings: List[str] = []
            if link_images:
                warnings.append(
                    "Dataset images are relative symlinks to the source job; "
                    "the archive contains dereferenced image bytes."
                )
            if project_ini_normalized:
                warnings.append(
                    "Absolute source paths in the copied project.ini were "
                    "normalized; COLMAP binary model files are unchanged."
                )
            manifest = NerfstudioDatasetManifest(
                job_id=safe_job_id,
                source_job_directory=self._relative_path(job_directory, staging),
                selected_sparse_model_id=selected_model.model_id,
                selected_sparse_model_path=self._relative_path(selected_path, staging),
                extracted_frame_count=extracted_frame_count,
                registered_image_count=len(registered_names),
                copied_image_count=len(registered_names),
                sparse_point_count=selected_model.sparse_point_count,
                camera_count=camera_count,
                missing_images=[],
                dataset_directory=".",
                warnings=warnings,
            )
            manifest.write_json(staging / "dataset-manifest.json")
            self._validate_dataset(staging, registered_names, manifest)

            if force and destination.exists():
                self._remove_existing_destination(destination)
            os.replace(str(staging), str(destination))

            created_archive: Optional[Path] = None
            if archive:
                created_archive = self._create_archive(
                    destination,
                    archive_path,
                    force=force,
                )
            return PreparedNerfstudioDataset(
                dataset_directory=destination,
                manifest=manifest,
                archive_path=created_archive,
            )
        except Exception:
            if staging.exists():
                shutil.rmtree(staging, ignore_errors=True)
            raise

    def select_best_model(
        self,
        sparse_directory: Path,
        requested_model_id: Optional[str] = None,
    ) -> SparseModelSummary:
        models = self.model_parser.summarize_models(sparse_directory)
        if not models:
            raise SparseModelNotFoundError(
                "No valid sparse COLMAP models found under %s" % sparse_directory
            )
        if requested_model_id is not None:
            safe_model_id = self._safe_identifier(requested_model_id, "model ID")
            for model in models:
                if model.model_id == safe_model_id:
                    return model
            raise SparseModelNotFoundError(
                "Sparse model '%s' was not found under %s"
                % (safe_model_id, sparse_directory)
            )
        return sorted(
            models,
            key=lambda model: (
                -(model.registered_image_count or 0),
                -(model.sparse_point_count or 0),
                model.model_id,
            ),
        )[0]

    @staticmethod
    def _safe_identifier(value: str, label: str) -> str:
        if not _SAFE_IDENTIFIER.fullmatch(value) or value in {".", ".."}:
            raise UnsafeDatasetPathError("Unsafe %s: %s" % (label, value))
        return value

    @staticmethod
    def _resolve_output_directory(
        output_directory: Optional[Path],
        job_directory: Path,
    ) -> Path:
        if output_directory is None:
            destination = job_directory / "nerfstudio-data"
        else:
            destination = Path(output_directory).expanduser().resolve()
        destination = destination.resolve()
        if destination == job_directory or destination in job_directory.parents:
            raise UnsafeDatasetPathError(
                "Output directory must not replace the job directory or its parent."
            )
        protected = {
            (job_directory / "images").resolve(),
            (job_directory / "sparse").resolve(),
            (job_directory / "logs").resolve(),
        }
        if destination in protected:
            raise UnsafeDatasetPathError(
                "Output directory overlaps source reconstruction artifacts."
            )
        return destination

    @staticmethod
    def _check_overwrite(
        destination: Path,
        archive_path: Path,
        archive: bool,
        force: bool,
    ) -> None:
        if destination.exists() and not force:
            raise DatasetOverwriteError(
                "Dataset already exists: %s. Pass --force to replace it."
                % destination
            )
        if archive and archive_path.exists() and not force:
            raise DatasetOverwriteError(
                "Dataset archive already exists: %s. Pass --force to replace it."
                % archive_path
            )

    def _export_text_model_if_needed(
        self,
        selected_model: Path,
        text_destination: Path,
        colmap_binary: str,
        log_path: Path,
    ) -> None:
        source_images_text = selected_model / "images.txt"
        source_cameras_text = selected_model / "cameras.txt"
        if source_images_text.is_file() and source_cameras_text.is_file():
            shutil.copy2(source_images_text, text_destination / "images.txt")
            shutil.copy2(source_cameras_text, text_destination / "cameras.txt")
            return
        try:
            self.process_runner.run(
                [
                    colmap_binary,
                    "model_converter",
                    "--input_path",
                    str(selected_model),
                    "--output_path",
                    str(text_destination),
                    "--output_type",
                    "TXT",
                ],
                log_path=log_path,
                cwd=selected_model.parent,
            )
        except ProcessRunnerError as error:
            raise ModelConversionError(
                "COLMAP model export failed: %s" % error
            ) from error
        if not (text_destination / "images.txt").is_file() or not (
            text_destination / "cameras.txt"
        ).is_file():
            raise DatasetValidationError(
                "COLMAP model_converter did not produce images.txt and cameras.txt."
            )

    @staticmethod
    def _read_registered_image_names(images_text: Path) -> List[str]:
        if not images_text.is_file():
            raise DatasetValidationError("COLMAP images.txt is missing.")
        names: List[str] = []
        expecting_metadata = True
        for line in images_text.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("#"):
                continue
            if expecting_metadata:
                if not line.strip():
                    continue
                fields = line.split()
                if len(fields) < 10:
                    raise DatasetValidationError(
                        "Malformed COLMAP image record in %s" % images_text
                    )
                names.append(" ".join(fields[9:]))
                expecting_metadata = False
            else:
                expecting_metadata = True
        if len(names) != len(set(names)):
            raise DatasetValidationError(
                "COLMAP model contains duplicate registered image names."
            )
        return names

    @staticmethod
    def _count_text_records(path: Path) -> int:
        if not path.is_file():
            raise DatasetValidationError("COLMAP text model file is missing: %s" % path)
        return sum(
            1
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        )

    def _validate_registered_sources(
        self,
        images_directory: Path,
        registered_names: Sequence[str],
    ) -> None:
        missing: List[str] = []
        for name in registered_names:
            self._safe_relative_image_path(name)
            source = (images_directory / name).resolve()
            if images_directory.resolve() not in source.parents or not source.is_file():
                missing.append(name)
        if missing:
            raise RegisteredImageMissingError(missing)

    def _copy_registered_images(
        self,
        source_root: Path,
        destination_root: Path,
        registered_names: Sequence[str],
        link_images: bool,
    ) -> None:
        for name in registered_names:
            relative = self._safe_relative_image_path(name)
            source = (source_root / relative).resolve()
            destination = destination_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if link_images:
                relative_target = os.path.relpath(source, start=destination.parent)
                destination.symlink_to(relative_target)
            else:
                shutil.copy2(source, destination)

    @staticmethod
    def _safe_relative_image_path(name: str) -> Path:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or not relative.parts:
            raise UnsafeDatasetPathError(
                "Unsafe registered image path in COLMAP model: %s" % name
            )
        return relative

    @classmethod
    def _copy_model(cls, source: Path, destination: Path) -> bool:
        for entry in source.iterdir():
            if entry.is_file():
                shutil.copy2(entry, destination / entry.name)
        project_ini = destination / "project.ini"
        return cls._make_project_ini_portable(project_ini)

    @staticmethod
    def _make_project_ini_portable(project_ini: Path) -> bool:
        if not project_ini.is_file():
            return False
        portable_values = {
            "database_path": "",
            "image_path": "../../../images",
            "input_path": ".",
            "output_path": ".",
            "snapshot_path": "",
            "image_list_path": "",
            "constant_rig_list_path": "",
            "constant_camera_list_path": "",
        }
        changed = False
        output_lines: List[str] = []
        for line in project_ini.read_text(encoding="utf-8").splitlines():
            key, separator, value = line.partition("=")
            if separator and key in portable_values and value != portable_values[key]:
                line = key + "=" + portable_values[key]
                changed = True
            output_lines.append(line)
        if changed:
            project_ini.write_text("\n".join(output_lines) + "\n", encoding="utf-8")
        return changed

    @staticmethod
    def _count_extracted_images(images_directory: Path) -> int:
        return sum(
            1
            for path in images_directory.rglob("*")
            if path.is_file() and path.suffix.lower() in _IMAGE_SUFFIXES
        )

    def _validate_dataset(
        self,
        dataset_directory: Path,
        registered_names: Sequence[str],
        manifest: NerfstudioDatasetManifest,
    ) -> None:
        images = dataset_directory / "images"
        model = dataset_directory / "colmap" / "sparse" / "0"
        if not images.is_dir():
            raise DatasetValidationError("Prepared dataset images directory is missing.")
        for filename in _REQUIRED_MODEL_FILES:
            if not (model / filename).is_file():
                raise DatasetValidationError(
                    "Prepared COLMAP model is missing %s." % filename
                )

        expected = {self._safe_relative_image_path(name).as_posix() for name in registered_names}
        actual = {
            path.relative_to(images).as_posix()
            for path in images.rglob("*")
            if path.is_file()
        }
        if not actual:
            raise DatasetValidationError("Prepared dataset contains no images.")
        if actual != expected:
            raise DatasetValidationError(
                "Prepared images do not exactly match COLMAP's registered images."
            )
        if manifest.registered_image_count != len(actual) or (
            manifest.copied_image_count != len(actual)
        ):
            raise DatasetValidationError(
                "Registered and copied image counts do not match."
            )
        for value in (
            manifest.source_job_directory,
            manifest.selected_sparse_model_path,
            manifest.dataset_directory,
        ):
            if Path(value).is_absolute():
                raise DatasetValidationError(
                    "Manifest contains a non-portable absolute path: %s" % value
                )
        project_ini = model / "project.ini"
        if project_ini.is_file():
            for line in project_ini.read_text(encoding="utf-8").splitlines():
                key, separator, value = line.partition("=")
                if separator and key.endswith("_path") and value:
                    if Path(value).is_absolute() or re.match(r"^[A-Za-z]:[\\/]", value):
                        raise DatasetValidationError(
                            "project.ini contains a non-portable absolute path: %s"
                            % value
                        )

    @staticmethod
    def _relative_path(target: Path, relative_to_directory: Path) -> str:
        return Path(os.path.relpath(target, start=relative_to_directory)).as_posix()

    @staticmethod
    def _remove_existing_destination(destination: Path) -> None:
        if destination.is_symlink() or destination.is_file():
            destination.unlink()
        else:
            shutil.rmtree(destination)

    @staticmethod
    def _create_archive(
        dataset_directory: Path,
        archive_path: Path,
        force: bool,
    ) -> Path:
        temporary = archive_path.with_suffix(archive_path.suffix + ".tmp")
        if temporary.exists():
            temporary.unlink()
        try:
            with tarfile.open(
                temporary,
                mode="w:gz",
                dereference=True,
            ) as archive_handle:
                archive_handle.add(
                    dataset_directory,
                    arcname=dataset_directory.name,
                    recursive=True,
                )
            if force and archive_path.exists():
                archive_path.unlink()
            os.replace(str(temporary), str(archive_path))
            return archive_path
        except Exception:
            if temporary.exists():
                temporary.unlink()
            raise
