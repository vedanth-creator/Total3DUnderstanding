"""Prepare a portable Nerfstudio dataset from an existing COLMAP job."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import tarfile
from typing import Any, BinaryIO, Dict, List, Optional, Sequence, Tuple
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


@dataclass(frozen=True)
class ColmapCamera:
    camera_id: int
    model_name: str
    width: int
    height: int
    parameters: Tuple[float, ...]


@dataclass(frozen=True)
class ColmapImage:
    image_id: int
    quaternion_wxyz: Tuple[float, float, float, float]
    translation_xyz: Tuple[float, float, float]
    camera_id: int
    name: str


@dataclass(frozen=True)
class ColmapPoint:
    point_id: int
    xyz: Tuple[float, float, float]
    rgb: Tuple[int, int, int]


@dataclass(frozen=True)
class ColmapBinaryModel:
    cameras: Dict[int, ColmapCamera]
    images: Tuple[ColmapImage, ...]
    points: Tuple[ColmapPoint, ...]

    @property
    def point_count(self) -> int:
        return len(self.points)


class ColmapBinaryModelReader:
    """Strict reader for COLMAP's documented sparse-model binary layout."""

    _CAMERA_MODELS = {
        0: ("SIMPLE_PINHOLE", 3),
        1: ("PINHOLE", 4),
        2: ("SIMPLE_RADIAL", 4),
        3: ("RADIAL", 5),
        4: ("OPENCV", 8),
        5: ("OPENCV_FISHEYE", 8),
        6: ("FULL_OPENCV", 12),
        7: ("FOV", 5),
        8: ("SIMPLE_RADIAL_FISHEYE", 4),
        9: ("RADIAL_FISHEYE", 5),
        10: ("THIN_PRISM_FISHEYE", 12),
    }
    _MAX_RECORDS = 10_000_000
    _MAX_NAME_BYTES = 1_048_576

    def read(self, model_directory: Path) -> ColmapBinaryModel:
        cameras = self._read_cameras(model_directory / "cameras.bin")
        images = self._read_images(model_directory / "images.bin")
        points = self._read_points(model_directory / "points3D.bin")
        if not cameras:
            raise DatasetValidationError("COLMAP model contains no cameras.")
        if not images:
            raise DatasetValidationError("COLMAP model contains no registered images.")
        missing_camera_ids = sorted(
            {image.camera_id for image in images if image.camera_id not in cameras}
        )
        if missing_camera_ids:
            raise DatasetValidationError(
                "COLMAP images reference missing camera IDs: %s"
                % ", ".join(str(value) for value in missing_camera_ids)
            )
        return ColmapBinaryModel(cameras, tuple(images), tuple(points))

    def _read_cameras(self, path: Path) -> Dict[int, ColmapCamera]:
        with self._open(path) as handle:
            count = self._count(handle, path)
            cameras: Dict[int, ColmapCamera] = {}
            for _ in range(count):
                camera_id, model_id, width, height = self._unpack(
                    handle, "<IiQQ", path
                )
                model = self._CAMERA_MODELS.get(model_id)
                if model is None:
                    raise DatasetValidationError(
                        "Unsupported COLMAP camera model ID %d in %s"
                        % (model_id, path)
                    )
                model_name, parameter_count = model
                parameters = self._unpack(
                    handle, "<%dd" % parameter_count, path
                )
                if camera_id in cameras:
                    raise DatasetValidationError(
                        "Duplicate COLMAP camera ID %d." % camera_id
                    )
                cameras[camera_id] = ColmapCamera(
                    camera_id,
                    model_name,
                    width,
                    height,
                    tuple(parameters),
                )
            self._require_eof(handle, path)
            return cameras

    def _read_images(self, path: Path) -> List[ColmapImage]:
        with self._open(path) as handle:
            count = self._count(handle, path)
            images: List[ColmapImage] = []
            names = set()
            image_ids = set()
            for _ in range(count):
                values = self._unpack(handle, "<I7dI", path)
                image_id = values[0]
                name = self._read_c_string(handle, path)
                point_count = self._count(handle, path)
                point_bytes = point_count * struct.calcsize("<2dq")
                if len(handle.read(point_bytes)) != point_bytes:
                    raise DatasetValidationError(
                        "Truncated COLMAP binary model file: %s" % path
                    )
                if image_id in image_ids or name in names:
                    raise DatasetValidationError(
                        "COLMAP model contains duplicate image IDs or names."
                    )
                image_ids.add(image_id)
                names.add(name)
                images.append(
                    ColmapImage(
                        image_id=image_id,
                        quaternion_wxyz=tuple(values[1:5]),
                        translation_xyz=tuple(values[5:8]),
                        camera_id=values[8],
                        name=name,
                    )
                )
            self._require_eof(handle, path)
            return images

    def _read_points(self, path: Path) -> List[ColmapPoint]:
        with self._open(path) as handle:
            count = self._count(handle, path)
            points: List[ColmapPoint] = []
            for _ in range(count):
                values = self._unpack(handle, "<Q3d3Bd", path)
                track_length = self._count(handle, path)
                track_bytes = track_length * struct.calcsize("<II")
                if len(handle.read(track_bytes)) != track_bytes:
                    raise DatasetValidationError(
                        "Truncated COLMAP binary model file: %s" % path
                    )
                points.append(
                    ColmapPoint(
                        point_id=values[0],
                        xyz=tuple(values[1:4]),
                        rgb=tuple(values[4:7]),
                    )
                )
            self._require_eof(handle, path)
            return points

    @staticmethod
    def _open(path: Path) -> BinaryIO:
        if not path.is_file():
            raise DatasetValidationError("COLMAP binary model file is missing: %s" % path)
        return path.open("rb")

    def _count(self, handle: BinaryIO, path: Path) -> int:
        count = self._unpack(handle, "<Q", path)[0]
        if count > self._MAX_RECORDS:
            raise DatasetValidationError(
                "Unreasonable record count in COLMAP binary model file: %s" % path
            )
        return count

    @staticmethod
    def _unpack(handle: BinaryIO, format_string: str, path: Path) -> Tuple[Any, ...]:
        size = struct.calcsize(format_string)
        payload = handle.read(size)
        if len(payload) != size:
            raise DatasetValidationError(
                "Truncated COLMAP binary model file: %s" % path
            )
        return struct.unpack(format_string, payload)

    def _read_c_string(self, handle: BinaryIO, path: Path) -> str:
        value = bytearray()
        while len(value) <= self._MAX_NAME_BYTES:
            byte = handle.read(1)
            if not byte:
                raise DatasetValidationError(
                    "Unterminated image name in COLMAP binary model file: %s" % path
                )
            if byte == b"\0":
                try:
                    return value.decode("utf-8")
                except UnicodeDecodeError as error:
                    raise DatasetValidationError(
                        "COLMAP image name is not valid UTF-8 in %s" % path
                    ) from error
            value.extend(byte)
        raise DatasetValidationError("COLMAP image name is too long in %s" % path)

    @staticmethod
    def _require_eof(handle: BinaryIO, path: Path) -> None:
        if handle.read(1):
            raise DatasetValidationError(
                "Unexpected trailing bytes in COLMAP binary model file: %s" % path
            )


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
        self.binary_model_reader = ColmapBinaryModelReader()

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
        binary_model = self.binary_model_reader.read(selected_path)
        registered_names = [image.name for image in binary_model.images]
        camera_count = len(binary_model.cameras)

        staging = destination.parent / (
            ".%s.tmp-%s" % (destination.name, uuid4().hex)
        )
        try:
            staging.mkdir(parents=True, exist_ok=False)
            staging_images = staging / "images"
            staging_model = staging / "colmap" / "sparse" / "0"
            staging_images.mkdir(parents=True)
            staging_model.mkdir(parents=True)

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
            transforms = self._build_transforms(binary_model)
            self._write_json(staging / "transforms.json", transforms)
            self._write_sparse_point_cloud(
                staging / "sparse_pc.ply", binary_model.points
            )
            self._validate_dataset(staging, registered_names, manifest, transforms)

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

    def _build_transforms(self, model: ColmapBinaryModel) -> Dict[str, Any]:
        referenced_camera_ids = {image.camera_id for image in model.images}
        if len(referenced_camera_ids) != 1:
            raise DatasetValidationError(
                "Nerfstudio export currently requires one camera shared by all "
                "video frames; found camera IDs: %s"
                % ", ".join(str(value) for value in sorted(referenced_camera_ids))
            )
        camera = model.cameras[next(iter(referenced_camera_ids))]
        intrinsics = self._nerfstudio_intrinsics(camera)
        frames = [
            {
                "file_path": "images/" + self._safe_relative_image_path(
                    image.name
                ).as_posix(),
                "transform_matrix": self._colmap_to_opengl_transform(image),
            }
            for image in model.images
        ]
        return dict(
            intrinsics,
            frames=frames,
            # This is Nerfstudio's current COLMAP-to-z-up world transform. It is
            # also applied to sparse_pc.ply so camera and point coordinates agree.
            applied_transform=[
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 0.0, 1.0, 0.0],
                [0.0, -1.0, 0.0, 0.0],
            ],
            ply_file_path="sparse_pc.ply",
        )

    @staticmethod
    def _nerfstudio_intrinsics(camera: ColmapCamera) -> Dict[str, Any]:
        parameters = camera.parameters
        model = camera.model_name
        if camera.width <= 0 or camera.height <= 0:
            raise DatasetValidationError("COLMAP camera dimensions must be positive.")

        camera_model = "OPENCV"
        distortion = {
            "k1": 0.0,
            "k2": 0.0,
            "k3": 0.0,
            "k4": 0.0,
            "p1": 0.0,
            "p2": 0.0,
        }
        if model == "SIMPLE_PINHOLE":
            focal_x, center_x, center_y = parameters
            focal_y = focal_x
        elif model == "PINHOLE":
            focal_x, focal_y, center_x, center_y = parameters
        elif model == "SIMPLE_RADIAL":
            focal_x, center_x, center_y, distortion["k1"] = parameters
            focal_y = focal_x
        elif model == "RADIAL":
            (
                focal_x,
                center_x,
                center_y,
                distortion["k1"],
                distortion["k2"],
            ) = parameters
            focal_y = focal_x
        elif model == "OPENCV":
            (
                focal_x,
                focal_y,
                center_x,
                center_y,
                distortion["k1"],
                distortion["k2"],
                distortion["p1"],
                distortion["p2"],
            ) = parameters
        elif model in {
            "OPENCV_FISHEYE",
            "SIMPLE_RADIAL_FISHEYE",
            "RADIAL_FISHEYE",
        }:
            camera_model = "OPENCV_FISHEYE"
            if model == "OPENCV_FISHEYE":
                (
                    focal_x,
                    focal_y,
                    center_x,
                    center_y,
                    distortion["k1"],
                    distortion["k2"],
                    distortion["k3"],
                    distortion["k4"],
                ) = parameters
            else:
                focal_x, center_x, center_y = parameters[:3]
                focal_y = focal_x
                radial = parameters[3:]
                for index, coefficient in enumerate(radial, start=1):
                    distortion["k%d" % index] = coefficient
        else:
            raise DatasetValidationError(
                "COLMAP camera model %s cannot be represented losslessly by "
                "Nerfstudio's OPENCV data parser." % model
            )

        numeric_values = (
            focal_x,
            focal_y,
            center_x,
            center_y,
            *distortion.values(),
        )
        if not all(math.isfinite(value) for value in numeric_values):
            raise DatasetValidationError("COLMAP camera contains non-finite intrinsics.")
        if focal_x <= 0 or focal_y <= 0:
            raise DatasetValidationError("COLMAP camera focal lengths must be positive.")
        return {
            "camera_model": camera_model,
            "fl_x": focal_x,
            "fl_y": focal_y,
            "cx": center_x,
            "cy": center_y,
            "w": camera.width,
            "h": camera.height,
            "camera_angle_x": 2.0 * math.atan(camera.width / (2.0 * focal_x)),
            **distortion,
        }

    @staticmethod
    def _colmap_to_opengl_transform(image: ColmapImage) -> List[List[float]]:
        # COLMAP stores world-to-camera poses with camera axes +X right, +Y down,
        # +Z forward. Invert that rigid transform, flip camera-local Y and Z to
        # OpenGL, then apply Nerfstudio's COLMAP-to-z-up world transform.
        w, x, y, z = image.quaternion_wxyz
        norm = math.sqrt(w * w + x * x + y * y + z * z)
        if not math.isfinite(norm) or norm <= 1e-12:
            raise DatasetValidationError(
                "COLMAP image %s has an invalid rotation quaternion." % image.name
            )
        w, x, y, z = (value / norm for value in (w, x, y, z))
        world_to_camera = [
            [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
            [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
            [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
        ]
        camera_to_world_rotation = [
            [world_to_camera[column][row] for column in range(3)]
            for row in range(3)
        ]
        translation = image.translation_xyz
        camera_center = [
            -sum(camera_to_world_rotation[row][column] * translation[column]
                 for column in range(3))
            for row in range(3)
        ]
        open_gl: List[List[float]] = []
        for row in range(3):
            open_gl.append(
                [
                    camera_to_world_rotation[row][0],
                    -camera_to_world_rotation[row][1],
                    -camera_to_world_rotation[row][2],
                    camera_center[row],
                ]
            )
        open_gl.append([0.0, 0.0, 0.0, 1.0])
        result = [
            list(open_gl[0]),
            list(open_gl[2]),
            [-value for value in open_gl[1]],
            [0.0, 0.0, 0.0, 1.0],
        ]
        result[2][3] = -open_gl[1][3]
        if not all(math.isfinite(value) for row in result for value in row):
            raise DatasetValidationError(
                "COLMAP image %s produces a non-finite camera transform." % image.name
            )
        return result

    @staticmethod
    def _write_sparse_point_cloud(
        destination: Path,
        points: Sequence[ColmapPoint],
    ) -> None:
        temporary = destination.with_suffix(destination.suffix + ".tmp")
        with temporary.open("w", encoding="ascii", newline="\n") as handle:
            handle.write("ply\nformat ascii 1.0\n")
            handle.write("element vertex %d\n" % len(points))
            handle.write(
                "property float x\nproperty float y\nproperty float z\n"
                "property uchar red\nproperty uchar green\nproperty uchar blue\n"
                "end_header\n"
            )
            for point in points:
                x, y, z = point.xyz
                red, green, blue = point.rgb
                if not all(math.isfinite(value) for value in point.xyz):
                    raise DatasetValidationError(
                        "COLMAP point %d has non-finite coordinates." % point.point_id
                    )
                handle.write(
                    "%.17g %.17g %.17g %d %d %d\n"
                    % (x, z, -y, red, green, blue)
                )
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))

    @staticmethod
    def _write_json(destination: Path, payload: Dict[str, Any]) -> None:
        temporary = destination.with_suffix(destination.suffix + ".tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))

    def _validate_dataset(
        self,
        dataset_directory: Path,
        registered_names: Sequence[str],
        manifest: NerfstudioDatasetManifest,
        transforms: Dict[str, Any],
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
        transforms_path = dataset_directory / "transforms.json"
        if not transforms_path.is_file():
            raise DatasetValidationError("Prepared dataset transforms.json is missing.")
        frame_paths = [frame.get("file_path") for frame in transforms.get("frames", [])]
        expected_frame_paths = [
            "images/" + self._safe_relative_image_path(name).as_posix()
            for name in registered_names
        ]
        if frame_paths != expected_frame_paths:
            raise DatasetValidationError(
                "transforms.json frames do not exactly match registered images."
            )
        if len(frame_paths) != len(set(frame_paths)):
            raise DatasetValidationError("transforms.json contains duplicate frames.")
        point_cloud_path = dataset_directory / str(transforms.get("ply_file_path", ""))
        if not point_cloud_path.is_file():
            raise DatasetValidationError(
                "Prepared dataset sparse point cloud is missing."
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
