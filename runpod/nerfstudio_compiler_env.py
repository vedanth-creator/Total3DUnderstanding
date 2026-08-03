"""Environment hook loaded automatically by the RunPod Nerfstudio venv."""

import os


GCC_11 = "/usr/bin/gcc-11"
GXX_11 = "/usr/bin/g++-11"


def configure_cuda_host_compiler() -> None:
    """Force PyTorch/Ninja CUDA extensions to use CUDA 11.8's supported GCC."""
    os.environ["CC"] = GCC_11
    os.environ["CXX"] = GXX_11
    os.environ["CUDAHOSTCXX"] = GXX_11
    # PyTorch's CUDA extension builder translates CC into nvcc's -ccbin. This
    # additional variable also covers build systems that invoke nvcc directly.
    os.environ["NVCC_CCBIN"] = GCC_11
    if os.path.isdir("/usr/local/cuda"):
        os.environ.setdefault("CUDA_HOME", "/usr/local/cuda")
    os.environ.setdefault("TORCH_CUDA_ARCH_LIST", "8.9")
    os.environ.setdefault("TCNN_CUDA_ARCHITECTURES", "89")


configure_cuda_host_compiler()
