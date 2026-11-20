"""License allowlist written by CELIAN, and the license rules built on it."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import replace
from pathlib import Path
from typing import Any

import pytest
import yaml
from catalog_findings import Finding, Severity
from catalog_licenses import (
    AcceptedLicenses,
    license_problems,
    load_accepted_licenses,
    network_copyleft,
)
from catalog_testing import TODAY
from check_catalog import Settings, run_check

WriteEntry = Callable[..., Path]
MVP_LICENSES = {
    "AGPL-3.0-only",
    "AGPL-3.0-or-later",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "MIT",
    "MPL-2.0",
    "PostgreSQL",
}


@pytest.fixture(scope="module")
def accepted() -> AcceptedLicenses:
    path = Settings.defaults(today=TODAY).licenses_path
    loaded = load_accepted_licenses(path, "accepted-licenses.yaml", TODAY)
    assert loaded.findings == ()
    assert loaded.licenses is not None
    return loaded.licenses


def test_allowlist_holds_the_mvp_licenses(accepted: AcceptedLicenses) -> None:
    assert {item.spdx_id for item in accepted.licenses.values()} == MVP_LICENSES
    assert {item.spdx_id for item in accepted.licenses.values() if item.network_copyleft} == {
        "AGPL-3.0-only",
        "AGPL-3.0-or-later",
    }
    assert dict(accepted.exceptions) == {}


@pytest.mark.parametrize(
    "expression",
    ["Apache-2.0", "MIT OR Apache-2.0", "MIT AND BSD-3-Clause", "PostgreSQL", "MPL-2.0"],
)
def test_accepted_expressions_pass(expression: str, accepted: AcceptedLicenses) -> None:
    assert license_problems(expression, accepted) == []


NOT_ACCEPTED = "is not in the CELIAN license allowlist: adding one takes a PR reviewed by [SECU]"
NOT_AN_EXCEPTION = (
    "is not an exception of the CELIAN license allowlist: adding one takes a PR reviewed by [SECU]"
)


@pytest.mark.parametrize(
    ("expression", "expected"),
    [
        ("BUSL-1.1", [f"'BUSL-1.1' {NOT_ACCEPTED}"]),
        ("MIT OR BUSL-1.1", [f"'BUSL-1.1' {NOT_ACCEPTED}"]),
        ("apache-2.0", ["'apache-2.0' is written 'Apache-2.0' in the CELIAN license allowlist"]),
        (
            "GPL-2.0-only WITH Classpath-exception-2.0",
            [f"'GPL-2.0-only' {NOT_ACCEPTED}", f"'Classpath-exception-2.0' {NOT_AN_EXCEPTION}"],
        ),
        ("Apache-2.0 WITH MIT", [f"'MIT' {NOT_AN_EXCEPTION}"]),
    ],
)
def test_license_problems_name_the_faulty_identifier(
    expression: str, expected: list[str], accepted: AcceptedLicenses
) -> None:
    assert license_problems(expression, accepted) == expected


@pytest.mark.parametrize(
    ("expression", "expected"),
    [
        ("AGPL-3.0-only", ["AGPL-3.0-only"]),
        ("MIT OR AGPL-3.0-or-later", ["AGPL-3.0-or-later"]),
        ("MPL-2.0", []),
        ("BUSL-1.1", []),
    ],
)
def test_network_copyleft_is_spotted_in_any_branch(
    expression: str, expected: list[str], accepted: AcceptedLicenses
) -> None:
    assert network_copyleft(expression, accepted) == expected


def test_network_copyleft_license_only_warns(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    minimal_entry["targets"]["local"]["license"] = "AGPL-3.0-only"

    findings = run_check([write_entry(minimal_entry)], settings)

    licensed = [(f.severity, f.rule) for f in findings if f.path == "targets/local/license"]
    assert licensed == [(Severity.WARNING, "network-copyleft")]


VALID_LICENSE = {
    "id": "MIT",
    "osi_page": "https://opensource.org/license/mit",
    "read_on": "2026-11-19",
}


def write_allowlist(tmp_path: Path, licenses: list[dict[str, Any]]) -> Path:
    path = tmp_path / "accepted-licenses.yaml"
    path.write_text(yaml.safe_dump({"licenses": licenses, "exceptions": []}), encoding="utf-8")
    return path


def errors_of(findings: list[Finding]) -> list[tuple[str, str]]:
    return [(f.path, f.rule) for f in findings if f.severity is Severity.ERROR]


@pytest.mark.parametrize(
    ("licenses", "expected"),
    [
        ([VALID_LICENSE, {**VALID_LICENSE}], [("licenses/1/id", "license-list")]),
        (
            [{**VALID_LICENSE, "read_on": "2026-11-20"}],
            [("licenses/0/read_on", "license-list")],
        ),
        (
            [{**VALID_LICENSE, "osi_page": "https://spdx.org/licenses/MIT.html"}],
            [("licenses/0/osi_page", "license-list:pattern")],
        ),
        (
            [{key: value for key, value in VALID_LICENSE.items() if key != "read_on"}],
            [("licenses/0", "license-list:required")],
        ),
        (
            [{**VALID_LICENSE, "note": "Ajout.\n"}],
            [("licenses/0/note", "trailing-newline")],
        ),
    ],
    ids=["duplicate", "future-date", "not-opensource-org", "no-read-on", "trailing-newline"],
)
def test_broken_allowlist_stops_the_check(
    licenses: list[dict[str, Any]],
    expected: list[tuple[str, str]],
    tmp_path: Path,
    settings: Settings,
) -> None:
    broken = replace(settings, licenses_path=write_allowlist(tmp_path, licenses))

    findings = run_check([Path(__file__).parent / "valid"], broken)

    assert errors_of(findings) == expected
    assert {Path(f.file).name for f in findings} == {"accepted-licenses.yaml"}
