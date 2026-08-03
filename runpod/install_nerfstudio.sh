#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
VENV_DIRECTORY="${NERFSTUDIO_VENV:-/workspace/nerfstudio-venv}"
PYTHON_BINARY="${PYTHON_BINARY:-python3}"

usage() {
  echo "Usage: $0 [--venv PATH] [--python EXECUTABLE]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      VENV_DIRECTORY="$2"
      shift 2
      ;;
    --python)
      PYTHON_BINARY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

gcc_major_version() {
  local compiler="$1"
  local version
  version="$($compiler -dumpfullversion -dumpversion)"
  echo "${version%%.*}"
}

run_apt() {
  if [[ "${EUID}" -eq 0 ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get "$@"
  else
    echo "Installing GCC 11 requires root access or sudo." >&2
    exit 1
  fi
}

current_gcc="missing"
current_gcc_major=0
if command -v gcc >/dev/null 2>&1; then
  current_gcc="$(gcc -dumpfullversion -dumpversion)"
  current_gcc_major="$(gcc_major_version gcc)"
fi
echo "Detected system GCC: ${current_gcc}"

install_gcc_11=false
if [[ "${current_gcc_major}" -gt 11 ]]; then
  echo "System GCC is newer than 11; GCC 11 will be installed for CUDA builds."
  install_gcc_11=true
fi
if [[ ! -x /usr/bin/gcc-11 || ! -x /usr/bin/g++-11 ]]; then
  install_gcc_11=true
fi

if [[ "${install_gcc_11}" == true ]]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "This bootstrap supports Ubuntu containers with apt-get." >&2
    exit 1
  fi
  run_apt update
  run_apt install -y gcc-11 g++-11 python3-venv
fi

if [[ "$(gcc_major_version /usr/bin/gcc-11)" != "11" ]]; then
  echo "Expected /usr/bin/gcc-11 to report major version 11." >&2
  exit 1
fi
if [[ "$(gcc_major_version /usr/bin/g++-11)" != "11" ]]; then
  echo "Expected /usr/bin/g++-11 to report major version 11." >&2
  exit 1
fi
if ! command -v nvcc >/dev/null 2>&1; then
  echo "nvcc is missing. Start from a CUDA 11.8 devel image, not a runtime image." >&2
  exit 1
fi

cuda_release="$(nvcc --version | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | tail -1)"
if [[ "${cuda_release}" != "11.8" ]]; then
  echo "Expected CUDA toolkit 11.8, but nvcc reports ${cuda_release:-unknown}." >&2
  exit 1
fi

python_version="$($PYTHON_BINARY -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "${python_version}" in
  3.9|3.10|3.11) ;;
  *)
    echo "Use Python 3.9, 3.10, or 3.11; detected ${python_version}." >&2
    exit 1
    ;;
esac

"${PYTHON_BINARY}" -m venv "${VENV_DIRECTORY}"
VENV_PYTHON="${VENV_DIRECTORY}/bin/python"
"${VENV_PYTHON}" -m pip install --upgrade \
  pip==24.3.1 \
  setuptools==75.6.0 \
  wheel==0.45.1
"${VENV_PYTHON}" -m pip install \
  torch==2.1.2+cu118 \
  torchvision==0.16.2+cu118 \
  --extra-index-url https://download.pytorch.org/whl/cu118
"${VENV_PYTHON}" -m pip install \
  --requirement "${REPOSITORY_ROOT}/runpod/requirements-nerfstudio.txt"

site_packages="$(${VENV_PYTHON} -c 'import site; print(site.getsitepackages()[0])')"
install -m 0644 \
  "${REPOSITORY_ROOT}/runpod/nerfstudio_compiler_env.py" \
  "${site_packages}/nerfstudio_compiler_env.py"
echo 'import nerfstudio_compiler_env' \
  > "${site_packages}/nerfstudio_compiler_env.pth"

"${VENV_PYTHON}" -c '
import os
import torch
assert os.environ["CC"] == "/usr/bin/gcc-11"
assert os.environ["CXX"] == "/usr/bin/g++-11"
assert os.environ["CUDAHOSTCXX"] == "/usr/bin/g++-11"
assert torch.version.cuda == "11.8", torch.version.cuda
print("PyTorch", torch.__version__, "CUDA", torch.version.cuda)
print("CUDA host compiler", os.environ["CC"])
'

echo
echo "Nerfstudio installation complete."
echo "Activate with: source ${VENV_DIRECTORY}/bin/activate"
echo "Verify with: ${REPOSITORY_ROOT}/runpod/verify_splatfacto.sh --venv ${VENV_DIRECTORY} --data <dataset>"
