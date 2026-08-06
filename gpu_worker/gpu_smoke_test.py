"""Run the same native gsplat GPU compatibility check used by smoke endpoints."""

import json

from gpu_worker.worker import run_gpu_compatibility_smoke_test


def main() -> int:
    result = run_gpu_compatibility_smoke_test()
    print(json.dumps(result, indent=2, sort_keys=True), flush=True)
    return 0 if result["status"] == "compatible" else 1


if __name__ == "__main__":
    raise SystemExit(main())
