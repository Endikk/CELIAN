"""What the catalog check reports: one finding per problem, never an exception."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from enum import Enum

ROOT_PATH = "(root)"


class Severity(Enum):
    ERROR = "error"
    WARNING = "warning"


@dataclass(frozen=True)
class Finding:
    """A problem in one file, located by a JSON path and named by its rule."""

    severity: Severity
    file: str
    path: str
    rule: str
    message: str

    def render(self) -> str:
        return f"{self.severity.value}: {self.file}: {self.path}: [{self.rule}] {self.message}"


def error(file: str, path: str, rule: str, message: str) -> Finding:
    return Finding(Severity.ERROR, file, path, rule, message)


def warning(file: str, path: str, rule: str, message: str) -> Finding:
    return Finding(Severity.WARNING, file, path, rule, message)


def json_path(parts: Iterable[str | int]) -> str:
    """Render ("targets", "local", 0) as targets/local/0, the empty path as (root)."""
    return "/".join(str(part) for part in parts) or ROOT_PATH


def has_errors(findings: Iterable[Finding]) -> bool:
    return any(finding.severity is Severity.ERROR for finding in findings)
