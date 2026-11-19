"""The examples of tests/catalog and the real catalog, end to end.

Each file of invalid/ states in its header the errors it must raise, and only
those: a path, then a schema keyword (validator) or a rule of the check, then
the message on the next line.
"""

from __future__ import annotations

import itertools
import re
from datetime import date
from pathlib import Path

import pytest
import yaml
from catalog_findings import Finding, Severity
from catalog_testing import CATALOG_DIR, INVALID_DIR, VALID_DIR
from check_catalog import Settings, run_check

Expected = tuple[str, str, str]

_PATH_LINE = re.compile(r"^#\s+path: (\S+)\s+(validator|rule): (\S+)\s*$")
_MESSAGE_LINE = re.compile(r"^#\s+message: (.+)$")


def expected_errors(path: Path) -> set[Expected]:
    """Read the (path, rule, message) triples declared in the file header."""
    lines = path.read_text(encoding="utf-8").splitlines()
    found: set[Expected] = set()
    for line, following in itertools.pairwise(lines):
        head = _PATH_LINE.match(line)
        if head is None:
            continue
        message = _MESSAGE_LINE.match(following)
        assert message is not None, f"{path.name}: no message line after {line!r}"
        json_path, kind, name = head.groups()
        rule = f"schema:{name}" if kind == "validator" else name
        found.add((json_path, rule, message.group(1)))
    return found


def errors_of(findings: list[Finding]) -> set[Expected]:
    return {(f.path, f.rule, f.message) for f in findings if f.severity is Severity.ERROR}


def latest_verification(directory: Path) -> date:
    """The most recent verified_on of a catalog, read with plain safe_load."""
    dates = [
        date.fromisoformat(target["verified_on"])
        for path in directory.glob("*.yaml")
        for target in yaml.safe_load(path.read_text(encoding="utf-8"))["targets"].values()
    ]
    return max(dates)


def test_minimal_example_passes(settings: Settings) -> None:
    findings = run_check([VALID_DIR], settings)

    assert errors_of(findings) == set()


def test_real_catalog_passes_on_its_last_verification_date() -> None:
    # The hook runs the real catalog against the real date. Here the date is
    # the last verification, so the test stays green until the next one.
    settings = Settings.defaults(today=latest_verification(CATALOG_DIR))

    findings = run_check([CATALOG_DIR], settings)

    assert errors_of(findings) == set()


@pytest.mark.parametrize("example", sorted(INVALID_DIR.glob("*.yaml")), ids=lambda path: path.stem)
def test_invalid_example_raises_exactly_its_declared_errors(
    example: Path, settings: Settings
) -> None:
    expected = expected_errors(example)
    assert expected, f"{example.name} declares no expected error"

    findings = run_check([example], settings)

    assert errors_of(findings) == expected
