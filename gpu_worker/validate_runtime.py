"""Fail the image build if the production worker runtime is incomplete."""

import ctypes
from importlib import metadata
import os
from pathlib import Path
import shutil
import subprocess
import sys


def require_command(arguments):
    completed = subprocess.run(
        arguments,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=120,
    )
    if completed.returncode != 0:
        raise RuntimeError("Command failed: %s" % " ".join(arguments))


def main() -> int:
    import torch
    import nerfstudio
    import gsplat
    import runpod
    import gpu_worker.worker
    from gsplat import csrc

    del nerfstudio, gsplat, runpod, gpu_worker.worker
    if torch.__version__ != "2.1.2+cu118":
        raise RuntimeError("Unexpected PyTorch version: %s" % torch.__version__)
    if torch.version.cuda != "11.8":
        raise RuntimeError("Unexpected PyTorch CUDA version: %s" % torch.version.cuda)
    if metadata.version("nerfstudio") != "1.1.5":
        raise RuntimeError("Unexpected Nerfstudio version.")
    if metadata.version("gsplat") != "1.4.0":
        raise RuntimeError("Unexpected gsplat version.")
    if metadata.version("runpod") != "1.7.13":
        raise RuntimeError("Unexpected RunPod SDK version.")
    if not Path(csrc.__file__).is_file():
        raise RuntimeError("Precompiled gsplat CUDA extension is missing.")
    if os.environ.get("TORCH_COMPILE_DISABLE") != "1":
        raise RuntimeError("TorchInductor must be disabled in the compiler-free runtime.")

    # Nerfstudio 1.1.5 decorates Splatfacto's get_viewmat helper with
    # torch.compile as an optional speed optimization. Exercise the same public
    # entry point here: with eager fallback enabled it must run without the C/C++
    # compiler that the production runtime intentionally excludes.
    eager_function = torch.compile(lambda value: value + 1)
    eager_result = eager_function(torch.tensor(1))
    if eager_result.item() != 2:
        raise RuntimeError("torch.compile eager fallback produced an invalid result.")

    require_command(["ns-train", "--help"])
    require_command(["ns-export", "gaussian-splat", "--help"])
    ctypes.CDLL("libcudart.so.11.0")

    forbidden = ("nvcc", "gcc", "g++", "cc", "c++", "cmake", "make")
    leaked = [name for name in forbidden if shutil.which(name) is not None]
    if leaked:
        raise RuntimeError("Build tools leaked into runtime: %s" % ", ".join(leaked))
    if os.environ.get("NVCC_FLAGS", "").find("allow-unsupported-compiler") >= 0:
        raise RuntimeError("Unsupported compiler override is forbidden.")

    print("Runtime validation passed", flush=True)
    print("Python", sys.version.split()[0], flush=True)
    print("PyTorch", torch.__version__, "CUDA", torch.version.cuda, flush=True)
    print("gsplat extension", csrc.__file__, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
