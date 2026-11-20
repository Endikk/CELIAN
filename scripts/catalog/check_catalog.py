"""Check the service catalog: schema, dates, links and licenses (ADR-009).

Usage, from the repository root:

    python scripts/catalog/check_catalog.py [--today YYYY-MM-DD] [PATH ...]

PATH is a catalog folder or an entry file; the default is catalog/. Today is
the UTC date unless --today injects one, for the tests. Every problem is
printed as "severity: file: JSON path: [rule] message". The exit code is 1
when there is at least one error; warnings alone exit 0.

Before any entry: the schema, then accepted-licenses.yaml; a problem in
either stops the check. Symbolic links are refused without being read.

Order of the checks, for each file: UTF-8, YAML structure (duplicate keys,
aliases, merge keys), yaml.safe_load, trailing line breaks, the JSON Schema,
then the rules of catalog_rules.py, which need an entry that passed the
schema. Ids are compared across files last.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path

from catalog_findings import ROOT_PATH, Finding, Severity, error, has_errors
from catalog_licenses import load_accepted_licenses
from catalog_rules import RuleContext, duplicate_id_findings, entry_findings
from catalog_schema import load_schema, validate_entry
from catalog_yaml import load_entry, trailing_newline_findings
from jsonschema import Draft202012Validator

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
ENTRY_SUFFIX = ".yaml"
FOLDER_EXTRAS = frozenset({"README.md"})
DESCRIPTION = "Check the service catalog: schema, dates, links and licenses (ADR-009)."
ISO_DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
SYMLINK_MESSAGE = "symbolic links are refused, and never followed: use a regular file or folder"


@dataclass(frozen=True)
class Settings:
    today: date
    schema_path: Path
    docs_dir: Path
    licenses_path: Path

    @classmethod
    def defaults(cls, today: date) -> Settings:
        return cls(
            today=today,
            schema_path=REPO_ROOT / "schema" / "catalog-entry.schema.json",
            docs_dir=REPO_ROOT / "docs",
            licenses_path=SCRIPT_DIR / "accepted-licenses.yaml",
        )


def utc_today(now: Callable[[], datetime] = lambda: datetime.now(UTC)) -> date:
    return now().astimezone(UTC).date()


@dataclass(frozen=True)
class Report:
    files: tuple[Path, ...]
    findings: tuple[Finding, ...]


def run_check(paths: Sequence[Path], settings: Settings) -> list[Finding]:
    return list(check(paths, settings).findings)


def check(paths: Sequence[Path], settings: Settings) -> Report:
    files, stray = _collect_files(paths)
    schema = load_schema(settings.schema_path, _shown(settings.schema_path))
    licenses = load_accepted_licenses(
        settings.licenses_path, _shown(settings.licenses_path), settings.today
    )
    if schema.validator is None or licenses.licenses is None:
        return Report(files, _ordered([*stray, *schema.findings, *licenses.findings]))
    ctx = RuleContext(settings.today, settings.docs_dir, licenses.licenses)
    findings: list[Finding] = list(stray)
    valid_ids: list[tuple[str, str]] = []
    for path in files:
        file_findings, entry_id = _check_file(path, schema.validator, ctx)
        findings.extend(file_findings)
        if entry_id is not None:
            valid_ids.append((_shown(path), entry_id))
    return Report(files, _ordered([*findings, *duplicate_id_findings(valid_ids)]))


def _check_file(
    path: Path, validator: Draft202012Validator, ctx: RuleContext
) -> tuple[list[Finding], str | None]:
    """Findings of one file, and its id when the entry passed the schema."""
    shown = _shown(path)
    loaded = load_entry(path, shown)
    if loaded.findings:
        return list(loaded.findings), None
    early = [
        *trailing_newline_findings(loaded.data, shown),
        *validate_entry(validator, loaded.data, shown),
    ]
    if any(finding.rule.startswith("schema:") for finding in early):
        return early, None
    return [*early, *entry_findings(loaded.data, path, shown, ctx)], loaded.data["id"]


def _collect_files(paths: Sequence[Path]) -> tuple[tuple[Path, ...], list[Finding]]:
    """Entry files to read, and findings for what must not be read.

    A symbolic link is refused before anything looks through it: is_dir and
    is_file follow links, so is_symlink comes first, for an argument as for a
    child of a folder ([SECU] review, S5).
    """
    files: list[Path] = []
    stray: list[Finding] = []
    for path in paths:
        if path.is_symlink():
            stray.append(error(_shown(path), ROOT_PATH, "symlink", SYMLINK_MESSAGE))
        elif not path.is_dir():
            files.append(path)
        else:
            children, problems = _folder_entries(path)
            files.extend(children)
            stray.extend(problems)
    return tuple(files), stray


def _folder_entries(folder: Path) -> tuple[list[Path], list[Finding]]:
    files: list[Path] = []
    stray: list[Finding] = []
    for child in sorted(folder.iterdir()):
        if child.is_symlink():
            stray.append(error(_shown(child), ROOT_PATH, "symlink", SYMLINK_MESSAGE))
        elif child.is_file() and child.suffix == ENTRY_SUFFIX:
            files.append(child)
        elif not (child.name in FOLDER_EXTRAS or child.name.startswith(".")):
            message = (
                f"{child.name} is not a catalog entry: the folder holds <id>.yaml and README.md"
            )
            stray.append(error(_shown(child), ROOT_PATH, "stray-file", message))
    return files, stray


def _shown(path: Path) -> str:
    """The path relative to the current folder if possible, links never resolved."""
    try:
        return str(path.absolute().relative_to(Path.cwd()))
    except ValueError:
        return str(path)


def _ordered(findings: list[Finding]) -> tuple[Finding, ...]:
    rank = {Severity.ERROR: 0, Severity.WARNING: 1}
    return tuple(
        sorted(findings, key=lambda f: (f.file, rank[f.severity], f.path, f.rule, f.message))
    )


def _iso_date(value: str) -> date:
    try:
        if ISO_DATE.fullmatch(value):
            return date.fromisoformat(value)
    except ValueError:
        pass
    raise argparse.ArgumentTypeError(f"expected a real date as YYYY-MM-DD, got {value!r}")


def _parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        default=[REPO_ROOT / "catalog"],
        help="catalog folders or entry files (default: catalog/)",
    )
    parser.add_argument(
        "--today",
        type=_iso_date,
        default=None,
        help="reference date, YYYY-MM-DD (default: today in UTC)",
    )
    return parser.parse_args(argv)


def _summary(report: Report) -> str:
    errors = sum(f.severity is Severity.ERROR for f in report.findings)
    warnings = len(report.findings) - errors

    def count(n: int, word: str) -> str:
        return f"{n} {word}" + ("" if n == 1 else "s")

    checked = count(len(report.files), "catalog file")
    return f"{checked} checked: {count(errors, 'error')}, {count(warnings, 'warning')}"


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    report = check(args.paths, Settings.defaults(today=args.today or utc_today()))
    for finding in report.findings:
        print(finding.render())
    print(_summary(report))
    return 1 if has_errors(report.findings) else 0


if __name__ == "__main__":
    sys.exit(main())
