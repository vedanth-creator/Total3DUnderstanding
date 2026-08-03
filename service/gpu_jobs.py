"""GPU job provider abstraction and RunPod Serverless HTTP implementation."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
import json
import os
from typing import Any, Dict, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class GPUJobState(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass(frozen=True)
class GPUJob:
    provider_job_id: str
    state: GPUJobState
    progress: Optional[float] = None
    stage: Optional[str] = None
    output: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class GPUJobProvider(ABC):
    @abstractmethod
    def submit_training_job(self, payload: Dict[str, Any]) -> str: ...
    @abstractmethod
    def get_training_job(self, provider_job_id: str) -> GPUJob: ...
    @abstractmethod
    def cancel_training_job(self, provider_job_id: str) -> None: ...


class RunPodGPUJobProvider(GPUJobProvider):
    def __init__(self, endpoint_id: str, api_key: str, api_base: str = "https://api.runpod.ai/v2", timeout: float = 30.0, opener: Any = urlopen) -> None:
        self.endpoint_id = endpoint_id
        self.api_key = api_key
        self.api_base = api_base.rstrip("/")
        self.timeout = timeout
        self.opener = opener

    @classmethod
    def from_environment(cls) -> "RunPodGPUJobProvider":
        endpoint = os.environ.get("RUNPOD_ENDPOINT_ID")
        api_key = os.environ.get("RUNPOD_API_KEY")
        if not endpoint or not api_key:
            raise ValueError("RUNPOD_ENDPOINT_ID and RUNPOD_API_KEY are required.")
        return cls(endpoint, api_key, os.environ.get("RUNPOD_API_BASE", "https://api.runpod.ai/v2"))

    def submit_training_job(self, payload: Dict[str, Any]) -> str:
        response = self._request("POST", "run", {"input": payload})
        job_id = response.get("id")
        if not isinstance(job_id, str) or not job_id:
            raise RuntimeError("RunPod submission response omitted job ID.")
        return job_id

    def get_training_job(self, provider_job_id: str) -> GPUJob:
        response = self._request("GET", "status/%s" % provider_job_id)
        raw = str(response.get("status", "")).upper()
        state = {
            "IN_QUEUE": GPUJobState.QUEUED,
            "IN_PROGRESS": GPUJobState.RUNNING,
            "COMPLETED": GPUJobState.COMPLETED,
            "FAILED": GPUJobState.FAILED,
            "CANCELLED": GPUJobState.CANCELLED,
            "TIMED_OUT": GPUJobState.FAILED,
        }.get(raw, GPUJobState.RUNNING)
        output = response.get("output") if isinstance(response.get("output"), dict) else None
        progress_data = response.get("progress") if isinstance(response.get("progress"), dict) else {}
        return GPUJob(str(response.get("id", provider_job_id)), state, progress_data.get("progress"), progress_data.get("stage"), output, response.get("error"))

    def cancel_training_job(self, provider_job_id: str) -> None:
        self._request("POST", "cancel/%s" % provider_job_id, {})

    def _request(self, method: str, suffix: str, payload: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = Request("%s/%s/%s" % (self.api_base, self.endpoint_id, suffix), data=data, method=method, headers={"Authorization": "Bearer " + self.api_key, "Content-Type": "application/json"})
        try:
            with self.opener(request, timeout=self.timeout) as response:
                decoded = json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, OSError, json.JSONDecodeError) as error:
            raise RuntimeError("RunPod API request failed: %s" % type(error).__name__) from error
        if not isinstance(decoded, dict):
            raise RuntimeError("RunPod API returned a malformed response.")
        return decoded
