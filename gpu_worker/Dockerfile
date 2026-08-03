FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    CC=/usr/bin/gcc-11 \
    CXX=/usr/bin/g++-11 \
    CUDAHOSTCXX=/usr/bin/g++-11 \
    NVCC_CCBIN=/usr/bin/gcc-11 \
    TORCH_CUDA_ARCH_LIST=8.9 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc-11 g++-11 python3 python3-pip curl && \
    rm -rf /var/lib/apt/lists/*
RUN python3 -m pip install pip==24.3.1 setuptools==75.6.0 wheel==0.45.1 && \
    python3 -m pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 \
      --extra-index-url https://download.pytorch.org/whl/cu118
COPY runpod/requirements-nerfstudio.txt /tmp/requirements-nerfstudio.txt
COPY gpu_worker/requirements.txt /tmp/requirements-worker.txt
RUN python3 -m pip install -r /tmp/requirements-nerfstudio.txt -r /tmp/requirements-worker.txt

WORKDIR /worker
COPY gpu_worker /worker/gpu_worker
CMD ["python3", "-m", "gpu_worker.worker"]
