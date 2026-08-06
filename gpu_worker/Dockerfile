# syntax=docker/dockerfile:1.7

ARG CUDA_VERSION=11.8.0
ARG UBUNTU_VERSION=22.04

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS builder

# CUDA translation units are memory-heavy under Docker Desktop/QEMU. Serial
# native compilation makes the linux/amd64 build reliable on modest builders.
ENV DEBIAN_FRONTEND=noninteractive \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    CC=/usr/bin/gcc-11 \
    CXX=/usr/bin/g++-11 \
    CUDAHOSTCXX=/usr/bin/g++-11 \
    NVCC_CCBIN=/usr/bin/gcc-11 \
    TORCH_CUDA_ARCH_LIST="8.6;8.9" \
    MAX_JOBS=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      cmake \
      gcc-11 \
      g++-11 \
      libgl1 \
      libglib2.0-0 \
      libgomp1 \
      libsm6 \
      libxext6 \
      libxrender1 \
      ninja-build \
      python3.10 \
      python3.10-dev \
      python3.10-venv \
      python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN python3.10 -m venv --copies "${VIRTUAL_ENV}" \
    && python -m pip install \
      pip==24.3.1 \
      setuptools==75.6.0 \
      wheel==0.45.1

RUN python -m pip install \
      torch==2.1.2+cu118 \
      torchvision==0.16.2+cu118 \
      --extra-index-url https://download.pytorch.org/whl/cu118

COPY runpod/requirements-nerfstudio.txt /tmp/requirements-nerfstudio.txt
COPY gpu_worker/requirements.txt /tmp/requirements-worker.txt
RUN python -m pip install \
      --requirement /tmp/requirements-nerfstudio.txt \
      --requirement /tmp/requirements-worker.txt \
    && python -m pip check

# The PyPI wheel normally JIT-compiles on first use. Reinstall from the pinned
# source release so gsplat.csrc is built into the venv instead. The 1.4.0 sdist
# does not carry its GLM submodule, so supply those headers in the builder.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libglm-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip uninstall --yes gsplat \
    && BUILD_NO_CUDA=0 python -m pip install \
      --no-build-isolation \
      --no-binary=gsplat \
      gsplat==1.4.0 \
    && python -m pip check \
    && python -c "from gsplat import csrc; print(csrc.__file__)" \
    && find "${VIRTUAL_ENV}" -type d -name __pycache__ -prune -exec rm -rf '{}' + \
    && find "${VIRTUAL_ENV}" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete


FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TORCH_CUDA_ARCH_LIST="8.6;8.9" \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Shared libraries retained for headless OpenCV/Open3D/PyMeshLab imports,
# image/video decoding, OpenMP kernels, TLS downloads, and worker uploads.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      ffmpeg \
      libgl1 \
      libglib2.0-0 \
      libgomp1 \
      libsm6 \
      libxext6 \
      libxrender1 \
      python3.10 \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/*

COPY --from=builder /opt/venv /opt/venv

WORKDIR /worker
COPY gpu_worker /worker/gpu_worker

RUN python3 -u -m gpu_worker.validate_runtime

LABEL org.opencontainers.image.title="Total3D Nerfstudio GPU Worker" \
      org.opencontainers.image.description="RunPod Serverless Splatfacto worker" \
      io.total3d.worker.command='["python3","-u","-m","gpu_worker.worker"]'

CMD ["python3", "-u", "-m", "gpu_worker.worker"]
