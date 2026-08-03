#!/usr/bin/env bash
set -euo pipefail

VENV_DIRECTORY="${NERFSTUDIO_VENV:-/workspace/nerfstudio-venv}"
DATASET_DIRECTORY=""

usage() {
  echo "Usage: $0 --data DATASET_DIRECTORY [--venv PATH]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)
      DATASET_DIRECTORY="$2"
      shift 2
      ;;
    --venv)
      VENV_DIRECTORY="$2"
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

if [[ -z "${DATASET_DIRECTORY}" ]]; then
  echo "--data is required." >&2
  exit 2
fi
DATASET_DIRECTORY="$(realpath "${DATASET_DIRECTORY}")"
if [[ ! -f "${DATASET_DIRECTORY}/transforms.json" ]]; then
  echo "Dataset is missing transforms.json: ${DATASET_DIRECTORY}" >&2
  exit 1
fi
if [[ ! -x "${VENV_DIRECTORY}/bin/ns-train" ]]; then
  echo "ns-train is missing from ${VENV_DIRECTORY}. Run install_nerfstudio.sh first." >&2
  exit 1
fi

source "${VENV_DIRECTORY}/bin/activate"

python - <<'PY'
import os
import shutil
import torch

expected = {
    "CC": "/usr/bin/gcc-11",
    "CXX": "/usr/bin/g++-11",
    "CUDAHOSTCXX": "/usr/bin/g++-11",
}
for name, value in expected.items():
    actual = os.environ.get(name)
    if actual != value:
        raise SystemExit(f"{name} is {actual!r}; expected {value!r}")
if shutil.which("nvcc") is None:
    raise SystemExit("nvcc is not available")
if not torch.cuda.is_available():
    raise SystemExit("PyTorch cannot access the RunPod GPU")
print("GPU:", torch.cuda.get_device_name(0))
print("PyTorch:", torch.__version__, "CUDA:", torch.version.cuda)
print("CUDA host compiler:", os.environ["CC"])
PY

verification_log="${DATASET_DIRECTORY}/splatfacto-verification.log"
set +e
ns-train splatfacto \
  --data "${DATASET_DIRECTORY}" \
  --max-num-iterations 1 \
  2>&1 | tee "${verification_log}"
training_status=${PIPESTATUS[0]}
set -e

if grep -q "unsupported GNU version" "${verification_log}"; then
  echo "Verification failed: nvcc rejected the configured host compiler." >&2
  exit 1
fi
if [[ "${training_status}" -ne 0 ]]; then
  echo "Verification failed: ns-train exited with ${training_status}." >&2
  exit "${training_status}"
fi

echo "Splatfacto completed one iteration without CUDA compiler errors."
