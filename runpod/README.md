# RunPod Nerfstudio installation

This setup targets an RTX 4090 pod using an Ubuntu 22.04 CUDA 11.8 **devel**
image. A devel image is required because gsplat compiles its CUDA extension on
first use and therefore needs `nvcc`.

The bootstrap pins the training stack to Nerfstudio 1.1.5, gsplat 1.4.0,
PyTorch 2.1.2, and CUDA 11.8. It detects the system GCC version. When the
system compiler is newer than GCC 11, it installs `gcc-11` and `g++-11`
automatically. It also installs a virtual-environment startup hook that sets
`CC`, `CXX`, `CUDAHOSTCXX`, and `NVCC_CCBIN` before Python imports gsplat. No
shell profile or manual environment editing is required, and the unsupported
compiler override is never used.

## Fresh pod

Choose a RunPod image based on `nvidia/cuda:11.8.0-devel-ubuntu22.04`, attach
persistent storage at `/workspace`, and clone this repository there. Then run:

```bash
cd /workspace/Total3DUnderstanding
./runpod/install_nerfstudio.sh
```

The default environment is `/workspace/nerfstudio-venv`. A different location
can be selected without editing files:

```bash
./runpod/install_nerfstudio.sh --venv /workspace/envs/nerfstudio
```

## Verify the exported dataset

Run the automated one-iteration training check:

```bash
./runpod/verify_splatfacto.sh \
  --data /workspace/Total3DUnderstanding/reconstruction/jobs/<job-id>/nerfstudio-data
```

The verifier confirms that the GPU, CUDA 11.8, GCC 11 hook, and `ns-train` are
available. It then runs exactly one Splatfacto iteration and fails if the
process exits unsuccessfully or its output contains `unsupported GNU version`.
The complete output is saved as `splatfacto-verification.log` inside the
dataset directory.

For normal training afterward:

```bash
source /workspace/nerfstudio-venv/bin/activate
ns-train splatfacto --data /absolute/path/to/nerfstudio-data
```
