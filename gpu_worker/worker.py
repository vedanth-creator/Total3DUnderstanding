"""RunPod-compatible, noninteractive Nerfstudio training worker."""

from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
from typing import Any, Dict, List, Optional, Sequence
from urllib.request import Request, urlopen


class WorkerError(RuntimeError):
    reason = "infrastructure_failure"


class InvalidDatasetError(WorkerError):
    reason = "invalid_dataset"


class TrainingError(WorkerError):
    reason = "training_failure"


@dataclass(frozen=True)
class WorkerLimits:
    maximum_download_bytes: int = 20 * 1024 * 1024 * 1024
    maximum_extracted_bytes: int = 40 * 1024 * 1024 * 1024
    maximum_output_bytes: int = 40 * 1024 * 1024 * 1024
    maximum_runtime_seconds: int = 6 * 60 * 60


def validate_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    required_strings = (
        "schema_version", "room_scan_id", "dataset_download_url",
        "requested_method", "correlation_id",
    )
    for key in required_strings:
        if not isinstance(payload.get(key), str) or not payload[key]:
            raise WorkerError("Missing or invalid %s." % key)
    if payload["schema_version"] != "1.0" or payload["requested_method"] != "splatfacto":
        raise WorkerError("Unsupported training request.")
    iterations = payload.get("maximum_iterations")
    if isinstance(iterations, bool) or not isinstance(iterations, int) or iterations < 1:
        raise WorkerError("maximum_iterations must be a positive integer.")
    uploads = payload.get("artifact_upload_urls")
    if not isinstance(uploads, dict):
        raise WorkerError("artifact_upload_urls must be an object.")
    for name in ("splat", "training_archive", "log", "result_manifest"):
        if not isinstance(uploads.get(name), str) or not uploads[name]:
            raise WorkerError("Missing artifact upload URL: %s." % name)
    return payload


def safe_extract(archive_path: Path, destination: Path, maximum_bytes: int) -> None:
    total = 0
    with tarfile.open(archive_path, "r:*") as archive:
        members = archive.getmembers()
        for member in members:
            member_path = Path(member.name)
            if member_path.is_absolute() or ".." in member_path.parts or not (member.isfile() or member.isdir()):
                raise InvalidDatasetError("Dataset archive contains an unsafe path.")
            total += max(member.size, 0)
            if total > maximum_bytes:
                raise InvalidDatasetError("Extracted dataset exceeds size limit.")
        archive.extractall(destination, members=members)


def validate_dataset(root: Path) -> Path:
    candidates = [root] + [path for path in root.iterdir() if path.is_dir()]
    dataset = next((path for path in candidates if (path / "transforms.json").is_file()), None)
    if dataset is None:
        raise InvalidDatasetError("Dataset is missing transforms.json.")
    if not (dataset / "sparse_pc.ply").is_file() or (dataset / "sparse_pc.ply").stat().st_size <= 0:
        raise InvalidDatasetError("Dataset is missing sparse_pc.ply.")
    try:
        transforms = json.loads((dataset / "transforms.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidDatasetError("transforms.json is invalid.") from error
    frames = transforms.get("frames")
    if not isinstance(frames, list) or not frames:
        raise InvalidDatasetError("transforms.json contains no frames.")
    for key in ("fl_x", "fl_y", "cx", "cy", "w", "h"):
        value = transforms.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise InvalidDatasetError("transforms.json is missing camera intrinsics.")
    for frame in frames:
        relative = Path(frame.get("file_path", "")) if isinstance(frame, dict) else Path("")
        image = (dataset / relative).resolve()
        if relative.is_absolute() or ".." in relative.parts or dataset.resolve() not in image.parents or not image.is_file():
            raise InvalidDatasetError("A transforms.json frame path is missing or unsafe.")
        matrix = frame.get("transform_matrix")
        if not isinstance(matrix, list) or len(matrix) != 4 or any(not isinstance(row, list) or len(row) != 4 or any(isinstance(value, bool) or not isinstance(value, (int, float)) for value in row) for row in matrix):
            raise InvalidDatasetError("A frame transform_matrix must be numeric 4x4 data.")
    return dataset


def run_command(arguments: Sequence[str], log, cwd: Path, timeout: int) -> None:
    log.write("COMMAND: %s\n" % " ".join(arguments))
    log.flush()
    try:
        completed = subprocess.run(list(arguments), cwd=str(cwd), stdout=log, stderr=subprocess.STDOUT, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise TrainingError("Command exceeded maximum runtime.") from error
    if completed.returncode != 0:
        raise TrainingError("Command failed with exit code %d: %s" % (completed.returncode, arguments[0]))


def download(url: str, destination: Path, maximum_bytes: int) -> None:
    request = Request(url, method="GET")
    with urlopen(request, timeout=120) as response, destination.open("wb") as output:
        total = 0
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > maximum_bytes:
                raise WorkerError("Dataset download exceeds size limit.")
            output.write(chunk)


def upload(url: str, source: Path) -> None:
    completed = subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--upload-file", str(source), url],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
        timeout=1800,
    )
    if completed.returncode != 0:
        raise WorkerError("Artifact upload failed.")


def execute_training(payload: Dict[str, Any], limits: WorkerLimits = WorkerLimits()) -> Dict[str, Any]:
    request = validate_payload(payload)
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="room-scan-training-") as temporary:
        workspace = Path(temporary)
        archive = workspace / "dataset.tar.gz"
        extracted = workspace / "dataset"
        output = workspace / "training"
        exports = workspace / "export"
        log_path = workspace / "training.log"
        extracted.mkdir()
        output.mkdir()
        exports.mkdir()
        try:
            download(request["dataset_download_url"], archive, limits.maximum_download_bytes)
            safe_extract(archive, extracted, limits.maximum_extracted_bytes)
            dataset = validate_dataset(extracted)
            with log_path.open("w", encoding="utf-8") as log:
                if request.get("startup_test", False):
                    run_command(["ns-train", "splatfacto", "--data", str(dataset), "--max-num-iterations", "1", "--output-dir", str(workspace / "startup"), "--vis", "tensorboard"], log, workspace, limits.maximum_runtime_seconds)
                run_command(["ns-train", "splatfacto", "--data", str(dataset), "--max-num-iterations", str(request["maximum_iterations"]), "--output-dir", str(output), "--vis", "tensorboard"], log, workspace, limits.maximum_runtime_seconds)
                configs = sorted(output.rglob("config.yml"), key=lambda path: path.stat().st_mtime, reverse=True)
                checkpoints = sorted(output.rglob("*.ckpt"))
                if not configs or not checkpoints:
                    raise TrainingError("Training did not produce config.yml and a checkpoint.")
                run_command(["ns-export", "gaussian-splat", "--load-config", str(configs[0]), "--output-dir", str(exports)], log, workspace, limits.maximum_runtime_seconds)
            splats = list(exports.rglob("splat.ply"))
            if not splats or splats[0].stat().st_size <= 0:
                raise TrainingError("ns-export did not produce a nonempty splat.ply.")
            training_archive = workspace / "nerfstudio-training.tar.gz"
            with tarfile.open(training_archive, "w:gz") as handle:
                handle.add(output, arcname="training")
                handle.add(exports, arcname="export")
            if training_archive.stat().st_size + splats[0].stat().st_size > limits.maximum_output_bytes:
                raise WorkerError("Training archive exceeds output-size limit.")
            manifest = {
                "schema_version": "1.0", "status": "completed",
                "room_scan_id": request["room_scan_id"],
                "correlation_id": request["correlation_id"],
                "method": "splatfacto", "iterations": request["maximum_iterations"],
                "duration_seconds": time.monotonic() - started,
            }
            manifest_path = workspace / "result.json"
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            urls = request["artifact_upload_urls"]
            upload(urls["splat"], splats[0])
            upload(urls["training_archive"], training_archive)
            upload(urls["log"], log_path)
            upload(urls["result_manifest"], manifest_path)
            return manifest
        except Exception as error:
            if log_path.exists():
                try:
                    upload(request["artifact_upload_urls"]["log"], log_path)
                except Exception:
                    pass
            failure = {"schema_version": "1.0", "status": "failed", "room_scan_id": request["room_scan_id"], "correlation_id": request["correlation_id"], "failure_reason": getattr(error, "reason", "infrastructure_failure"), "error": str(error)[:1000]}
            try:
                failure_path = workspace / "result.json"
                failure_path.write_text(json.dumps(failure, indent=2) + "\n", encoding="utf-8")
                upload(request["artifact_upload_urls"]["result_manifest"], failure_path)
            except Exception:
                pass
            return failure


def handler(event: Dict[str, Any]) -> Dict[str, Any]:
    payload = event.get("input") if isinstance(event, dict) else None
    if not isinstance(payload, dict):
        return {"schema_version": "1.0", "status": "failed", "failure_reason": "invalid_request", "error": "RunPod input must be an object."}
    return execute_training(payload)


if __name__ == "__main__":
    import runpod
    runpod.serverless.start({"handler": handler})
