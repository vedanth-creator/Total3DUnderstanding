import os
from pathlib import Path
import subprocess
import unittest
from unittest import mock

from runpod.nerfstudio_compiler_env import configure_cuda_host_compiler


class RunPodSetupTest(unittest.TestCase):
    repository_root = Path(__file__).resolve().parents[1]
    install_script = repository_root / "runpod" / "install_nerfstudio.sh"
    verify_script = repository_root / "runpod" / "verify_splatfacto.sh"

    def test_shell_scripts_have_valid_bash_syntax(self) -> None:
        for script in (self.install_script, self.verify_script):
            subprocess.run(["bash", "-n", str(script)], check=True)

    def test_compiler_hook_forces_gcc_11_without_unsupported_override(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            configure_cuda_host_compiler()
            self.assertEqual(os.environ["CC"], "/usr/bin/gcc-11")
            self.assertEqual(os.environ["CXX"], "/usr/bin/g++-11")
            self.assertEqual(os.environ["CUDAHOSTCXX"], "/usr/bin/g++-11")
            self.assertEqual(os.environ["NVCC_CCBIN"], "/usr/bin/gcc-11")
            self.assertEqual(os.environ["TORCH_CUDA_ARCH_LIST"], "8.9")

        combined = self.install_script.read_text() + self.verify_script.read_text()
        self.assertNotIn("allow-unsupported-compiler", combined.lower())

    def test_installer_detects_newer_gcc_and_installs_version_11(self) -> None:
        contents = self.install_script.read_text()
        self.assertIn('"${current_gcc_major}" -gt 11', contents)
        self.assertIn("install -y gcc-11 g++-11", contents)
        self.assertIn("nerfstudio_compiler_env.pth", contents)

    def test_verifier_runs_required_single_iteration_command(self) -> None:
        contents = self.verify_script.read_text()
        self.assertIn("ns-train splatfacto", contents)
        self.assertIn('--data "${DATASET_DIRECTORY}"', contents)
        self.assertIn("--max-num-iterations 1", contents)
        self.assertIn("unsupported GNU version", contents)


if __name__ == "__main__":
    unittest.main()
