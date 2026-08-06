"""Verify that the precompiled gsplat extension embeds required CUDA cubins."""

import argparse
from pathlib import Path
import shutil
import subprocess
from typing import Iterable, Optional, Sequence


def inspect_gsplat_binary(required_architectures: Iterable[str]) -> str:
    from gsplat import csrc

    extension = Path(csrc.__file__).resolve()
    if not extension.is_file():
        raise RuntimeError("The compiled gsplat CUDA extension is missing: %s" % extension)
    cuobjdump = shutil.which("cuobjdump")
    if cuobjdump is None:
        raise RuntimeError("cuobjdump is required to validate the gsplat CUDA extension.")
    completed = subprocess.run(
        [cuobjdump, "--list-elf", str(extension)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        text=True,
        timeout=120,
    )
    output = completed.stdout
    print("gsplat CUDA extension: %s" % extension, flush=True)
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    if completed.returncode != 0:
        raise RuntimeError("cuobjdump failed with exit code %d." % completed.returncode)
    missing = [architecture for architecture in required_architectures if architecture not in output]
    if missing:
        raise RuntimeError(
            "gsplat CUDA extension is missing required architecture(s): %s"
            % ", ".join(missing)
        )
    return output


def main(arguments: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--require-architecture",
        action="append",
        required=True,
        help="CUDA cubin architecture that must appear in cuobjdump output (for example sm_86).",
    )
    parsed = parser.parse_args(arguments)
    inspect_gsplat_binary(parsed.require_architecture)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
