import io
import os
from contextlib import redirect_stdout
from pathlib import Path
import subprocess
import sys
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest import mock

from gpu_worker import worker
from gpu_worker.verify_gsplat_binary import inspect_gsplat_binary


class GPUWorkerCompatibilityTest(unittest.TestCase):
    def test_binary_inspection_requires_each_requested_architecture(self):
        with tempfile.TemporaryDirectory() as temporary:
            extension = Path(temporary) / "csrc.so"
            extension.write_bytes(b"compiled-extension")
            gsplat = ModuleType("gsplat")
            gsplat.csrc = SimpleNamespace(__file__=str(extension))
            completed = subprocess.CompletedProcess(
                args=["cuobjdump"],
                returncode=0,
                stdout="ELF file 1: csrc.1.sm_86.cubin\nELF file 2: csrc.2.sm_89.cubin\n",
            )
            with mock.patch.dict(sys.modules, {"gsplat": gsplat}), \
                    mock.patch("gpu_worker.verify_gsplat_binary.shutil.which", return_value="/usr/bin/cuobjdump"), \
                    mock.patch("gpu_worker.verify_gsplat_binary.subprocess.run", return_value=completed):
                output = inspect_gsplat_binary(["sm_86", "sm_89"])
                self.assertIn("sm_86", output)
                with self.assertRaisesRegex(RuntimeError, "sm_90"):
                    inspect_gsplat_binary(["sm_86", "sm_90"])

    def test_startup_diagnostics_are_allow_listed_and_do_not_leak_environment(self):
        diagnostics = {
            "cuda_available": True,
            "device_name": "NVIDIA RTX A5000",
            "device_capability": [8, 6],
            "torch_cuda_version": "11.8",
            "torch_version": "2.1.2+cu118",
            "gsplat_version": "1.4.0",
            "gsplat_extension_path": "/opt/venv/gsplat/csrc.so",
        }
        output = io.StringIO()
        with mock.patch.dict(
            os.environ,
            {"R2_SECRET_ACCESS_KEY": "never-print-this", "DATASET_URL": "https://signed.example/secret"},
        ), mock.patch.object(worker, "collect_gpu_runtime_diagnostics", return_value=diagnostics), redirect_stdout(output):
            returned = worker.emit_startup_gpu_diagnostics()
        self.assertEqual(returned, diagnostics)
        logged = output.getvalue()
        self.assertIn("NVIDIA RTX A5000", logged)
        self.assertIn('"device_capability": [8, 6]', logged)
        self.assertNotIn("never-print-this", logged)
        self.assertNotIn("signed.example", logged)

    def test_smoke_mode_bypasses_payload_validation_and_full_training(self):
        compatible = {
            "schema_version": "1.0",
            "status": "compatible",
            "mode": "gpu_compatibility_smoke_test",
        }
        with mock.patch.dict(os.environ, {worker.GPU_SMOKE_TEST_ENVIRONMENT_VARIABLE: "1"}), \
                mock.patch.object(worker, "run_gpu_compatibility_smoke_test", return_value=compatible), \
                mock.patch.object(worker, "execute_training") as training:
            result = worker.handler({"input": {"intentionally": "not-a-training-payload"}})
        self.assertEqual(result, compatible)
        training.assert_not_called()

    def test_smoke_test_returns_structured_native_extension_failure(self):
        diagnostics = {"device_name": "NVIDIA RTX A5000", "device_capability": [8, 6]}
        with mock.patch.object(worker, "collect_gpu_runtime_diagnostics", return_value=diagnostics), \
                mock.patch.object(
                    worker,
                    "exercise_gsplat_cuda_extension",
                    side_effect=RuntimeError("CUDA error: no kernel image is available"),
                ):
            result = worker.run_gpu_compatibility_smoke_test()
        self.assertEqual(result["status"], "incompatible")
        self.assertEqual(result["failure_reason"], "gpu_incompatible")
        self.assertEqual(result["error_type"], "RuntimeError")
        self.assertIn("no kernel image", result["error"])
        self.assertEqual(result["diagnostics"], diagnostics)

    def test_smoke_test_success_reports_the_gsplat_operation(self):
        diagnostics = {"device_name": "NVIDIA RTX A5000", "device_capability": [8, 6]}
        operation = {
            "operation": "quat_scale_to_covar_preci",
            "covariance_shape": [1, 3, 3],
            "precision_shape": [1, 3, 3],
            "finite": True,
        }
        with mock.patch.object(worker, "collect_gpu_runtime_diagnostics", return_value=diagnostics), \
                mock.patch.object(worker, "exercise_gsplat_cuda_extension", return_value=operation):
            result = worker.run_gpu_compatibility_smoke_test()
        self.assertEqual(result["status"], "compatible")
        self.assertEqual(result["gsplat_operation"], operation)


if __name__ == "__main__":
    unittest.main()
