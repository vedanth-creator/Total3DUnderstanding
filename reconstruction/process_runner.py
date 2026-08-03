"""Safe subprocess execution with per-command log files."""

from dataclasses import dataclass
from pathlib import Path
import shutil
import subprocess
from typing import Mapping, Optional, Sequence


class ProcessRunnerError(RuntimeError):
    """Base error for external reconstruction commands."""


class MissingExecutableError(ProcessRunnerError):
    def __init__(self, executable: str) -> None:
        super().__init__(
            "Required executable '%s' was not found. Install it or provide its "
            "path with the corresponding CLI option." % executable
        )
        self.executable = executable


class CommandExecutionError(ProcessRunnerError):
    def __init__(self, arguments: Sequence[str], return_code: int, log_path: Path) -> None:
        command_name = Path(arguments[0]).name if arguments else "external command"
        super().__init__(
            "%s failed with exit code %d. See log: %s"
            % (command_name, return_code, log_path)
        )
        self.arguments = tuple(arguments)
        self.return_code = return_code
        self.log_path = log_path


@dataclass(frozen=True)
class CommandResult:
    arguments: tuple
    return_code: int
    log_path: Path


class ProcessRunner:
    def resolve_executable(self, executable: str) -> str:
        candidate = Path(executable).expanduser()
        if candidate.parent != Path(".") or candidate.is_absolute():
            resolved = candidate.resolve()
            if resolved.is_file() and resolved.stat().st_mode & 0o111:
                return str(resolved)
            raise MissingExecutableError(executable)

        located = shutil.which(executable)
        if located is None:
            raise MissingExecutableError(executable)
        return located

    def run(
        self,
        arguments: Sequence[str],
        log_path: Path,
        cwd: Optional[Path] = None,
        environment: Optional[Mapping[str, str]] = None,
    ) -> CommandResult:
        if not arguments:
            raise ValueError("A subprocess argument array must not be empty.")

        resolved_arguments = [self.resolve_executable(str(arguments[0]))]
        resolved_arguments.extend(str(argument) for argument in arguments[1:])
        log_path.parent.mkdir(parents=True, exist_ok=True)

        with log_path.open("w", encoding="utf-8") as log_handle:
            log_handle.write("Command: %s\n\n" % " ".join(resolved_arguments))
            log_handle.flush()
            completed = subprocess.run(
                resolved_arguments,
                cwd=str(cwd) if cwd is not None else None,
                env=dict(environment) if environment is not None else None,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                check=False,
                shell=False,
            )

        if completed.returncode != 0:
            raise CommandExecutionError(
                resolved_arguments,
                completed.returncode,
                log_path,
            )
        return CommandResult(
            arguments=tuple(resolved_arguments),
            return_code=completed.returncode,
            log_path=log_path,
        )
