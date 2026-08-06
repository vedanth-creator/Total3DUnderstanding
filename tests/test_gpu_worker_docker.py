from pathlib import Path
import unittest


class GPUWorkerDockerTest(unittest.TestCase):
    root = Path(__file__).resolve().parents[1]
    dockerfile = root / "gpu_worker" / "Dockerfile"
    validator = root / "gpu_worker" / "validate_runtime.py"
    binary_validator = root / "gpu_worker" / "verify_gsplat_binary.py"

    def setUp(self):
        self.contents = self.dockerfile.read_text(encoding="utf-8")

    def test_uses_cuda_devel_builder_and_runtime_final_stage(self):
        self.assertIn("-devel-ubuntu${UBUNTU_VERSION} AS builder", self.contents)
        self.assertIn("-runtime-ubuntu${UBUNTU_VERSION} AS runtime", self.contents)
        runtime = self.contents.split(" AS runtime", 1)[1]
        for package in ("gcc-11", "g++-11", "python3.10-dev", "build-essential", "cmake"):
            self.assertNotIn("      " + package + " \\\n", runtime)

    def test_preserves_pins_and_target_architectures(self):
        for pin in (
            "torch==2.1.2+cu118",
            "torchvision==0.16.2+cu118",
            "gsplat==1.4.0",
            'TORCH_CUDA_ARCH_LIST="8.6;8.9"',
            'NVCC_FLAGS="-gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89"',
            "CC=/usr/bin/gcc-11",
            "CXX=/usr/bin/g++-11",
            "CUDAHOSTCXX=/usr/bin/g++-11",
            "NVCC_CCBIN=/usr/bin/gcc-11",
        ):
            self.assertIn(pin, self.contents)

    def test_gsplat_is_compiled_in_builder_not_at_runtime(self):
        self.assertIn("--no-binary=gsplat", self.contents)
        self.assertIn("pip install --verbose", self.contents)
        self.assertIn('from gsplat import csrc', self.binary_validator.read_text(encoding="utf-8"))
        runtime = self.contents.split(" AS runtime", 1)[1]
        self.assertNotIn("pip install", runtime)
        self.assertIn("gpu_worker.validate_runtime", runtime)

    def test_builder_fails_without_required_gsplat_cubins(self):
        self.assertIn("python /tmp/verify_gsplat_binary.py", self.contents)
        self.assertIn("--require-architecture sm_86", self.contents)
        self.assertIn("--require-architecture sm_89", self.contents)
        validator = self.binary_validator.read_text(encoding="utf-8")
        self.assertIn('[cuobjdump, "--list-elf", str(extension)]', validator)
        self.assertIn("if missing:", validator)

    def test_runtime_validation_covers_required_imports_and_commands(self):
        contents = self.validator.read_text(encoding="utf-8")
        for expected in (
            "import torch",
            "import nerfstudio",
            "import gsplat",
            "import runpod",
            "import gpu_worker.worker",
            '["ns-train", "--help"]',
            '["ns-export", "gaussian-splat", "--help"]',
            'ctypes.CDLL("libcudart.so.11.0")',
            '"nvcc"',
            '"gcc"',
            'os.environ.get("TORCH_COMPILE_DISABLE") != "1"',
            "torch.compile(lambda value: value + 1)",
        ):
            self.assertIn(expected, contents)

    def test_runtime_uses_eager_fallback_without_restoring_a_compiler(self):
        runtime = self.contents.split(" AS runtime", 1)[1]
        self.assertIn("TORCH_COMPILE_DISABLE=1", runtime)
        for package in ("gcc-11", "g++-11", "build-essential", "cmake"):
            self.assertNotIn("      " + package + " \\\n", runtime)

    def test_worker_command_is_exact_and_no_unsupported_override(self):
        self.assertIn('CMD ["python3", "-u", "-m", "gpu_worker.worker"]', self.contents)
        self.assertNotIn("allow-unsupported-compiler", self.contents.lower())


if __name__ == "__main__":
    unittest.main()
