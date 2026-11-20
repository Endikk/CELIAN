"""Rules the schema cannot express: dates, freshness, links, licenses."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import replace
from datetime import date
from pathlib import Path
from typing import Any

import pytest
from catalog_findings import Finding, Severity
from catalog_rules import add_months
from check_catalog import Settings, run_check

WriteEntry = Callable[..., Path]


def rules_of(findings: list[Finding], severity: Severity) -> list[tuple[str, str]]:
    return [(f.path, f.rule) for f in findings if f.severity is severity]


def check_on(day: date, path: Path, settings: Settings) -> list[Finding]:
    return run_check([path], replace(settings, today=day))


@pytest.mark.parametrize(
    ("start", "months", "expected"),
    [
        (date(2026, 11, 19), 6, date(2027, 5, 19)),
        (date(2026, 8, 26), 12, date(2027, 8, 26)),
        (date(2026, 8, 31), 6, date(2027, 2, 28)),
        (date(2027, 8, 31), 6, date(2028, 2, 29)),
        (date(2024, 2, 29), 12, date(2025, 2, 28)),
        (date(2026, 12, 15), 1, date(2027, 1, 15)),
    ],
)
def test_add_months_counts_calendar_months_and_clamps_to_month_end(
    start: date, months: int, expected: date
) -> None:
    assert add_months(start, months) == expected


@pytest.mark.parametrize(
    ("today", "expected"),
    [
        (date(2027, 4, 18), None),
        (date(2027, 4, 19), Severity.WARNING),
        (date(2027, 5, 18), Severity.WARNING),
        (date(2027, 5, 19), Severity.ERROR),
    ],
)
def test_verification_warns_in_its_last_month_and_fails_at_six_months(
    today: date,
    expected: Severity | None,
    minimal_entry: dict[str, Any],
    write_entry: WriteEntry,
    settings: Settings,
) -> None:
    # minimal.yaml is verified on 2026-11-19 on both targets.
    findings = check_on(today, write_entry(minimal_entry), settings)

    stale = [
        f.severity
        for f in findings
        if (f.path, f.rule) == ("targets/local/verified_on", "stale-verification")
    ]
    assert stale == ([expected] if expected else [])


@pytest.mark.parametrize(
    ("today", "expected_error"),
    [(date(2027, 8, 25), False), (date(2027, 8, 26), True)],
)
def test_release_older_than_twelve_months_fails_on_the_anniversary(
    today: date,
    expected_error: bool,
    minimal_entry: dict[str, Any],
    write_entry: WriteEntry,
    settings: Settings,
) -> None:
    # The kind case of ADR-004: last release 2026-08-26, limit 2027-08-26.
    local = minimal_entry["targets"]["local"]
    local["last_release_on"] = "2026-08-26"
    for target in minimal_entry["targets"].values():
        target["verified_on"] = "2027-08-01"
        target["sources"][0]["read_on"] = "2027-08-01"

    findings = check_on(today, write_entry(minimal_entry), settings)

    release = ("targets/local/last_release_on", "release-age")
    assert (release in rules_of(findings, Severity.ERROR)) is expected_error


def test_every_date_field_is_checked_against_today(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    local = minimal_entry["targets"]["local"]
    local["verified_on"] = "2026-11-20"
    local["sources"][0]["read_on"] = "2026-11-20"
    local["artifacts"] = [
        {
            "platform": "linux-amd64",
            "sha256": "a" * 64,
            "source": "https://example.invalid/oss/releases",
            "read_on": "2026-11-20",
        }
    ]

    findings = run_check([write_entry(minimal_entry)], settings)

    assert sorted(rules_of(findings, Severity.ERROR)) == [
        ("targets/local/artifacts/0/read_on", "future-date"),
        ("targets/local/sources/0/read_on", "future-date"),
        ("targets/local/verified_on", "future-date"),
    ]


def test_bench_reference_must_exist_too(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    minimal_entry["targets"]["gcp"]["decisions"]["bench"] = ["BENCH-003", "BENCH-998"]

    findings = run_check([write_entry(minimal_entry)], settings)

    assert rules_of(findings, Severity.ERROR) == [
        ("targets/gcp/decisions/bench/1", "decision-link")
    ]


def test_pending_items_and_missing_common_standard_only_warn(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    minimal_entry["targets"]["gcp"]["pending"] = [
        {"topic": "cluster-mode", "owner": "OPS", "note": "Autopilot ou Standard."}
    ]

    findings = run_check([write_entry(minimal_entry)], settings)

    assert rules_of(findings, Severity.ERROR) == []
    assert sorted(rules_of(findings, Severity.WARNING)) == [
        ("targets", "standards"),
        ("targets/gcp/pending", "pending"),
    ]


def test_shared_standard_silences_the_standards_warning(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    for target in minimal_entry["targets"].values():
        target["standards"] = ["kubernetes-api"]

    findings = run_check([write_entry(minimal_entry)], settings)

    assert findings == []


def test_same_id_in_two_files_is_reported(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    first = write_entry(minimal_entry, "a/minimal.yaml")
    second = write_entry(minimal_entry, "b/minimal.yaml")

    findings = run_check([first, second], settings)

    assert rules_of(findings, Severity.ERROR) == [("id", "duplicate-id")]


def test_catalog_folder_accepts_only_entries_and_its_readme(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    folder = write_entry(minimal_entry).parent
    (folder / "README.md").write_text("# Catalogue\n", encoding="utf-8")
    (folder / ".gitkeep").write_text("", encoding="utf-8")
    (folder / "other.yml").write_text("id: other\n", encoding="utf-8")

    findings = run_check([folder], settings)

    errors = [f for f in findings if f.severity is Severity.ERROR]
    assert [(Path(f.file).name, f.rule) for f in errors] == [("other.yml", "stray-file")]


def test_trailing_newline_is_caught_in_nested_strings_and_lists(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    gcp = minimal_entry["targets"]["gcp"]
    gcp["notes"] = "Texte libre.\n"
    gcp["sources"][0]["establishes"] = "Un fait.\n"

    findings = run_check([write_entry(minimal_entry)], settings)

    assert sorted(rules_of(findings, Severity.ERROR)) == [
        ("targets/gcp/notes", "trailing-newline"),
        ("targets/gcp/sources/0/establishes", "trailing-newline"),
    ]


def dated(entry: dict[str, Any], day: str) -> dict[str, Any]:
    """Set every date of the minimal entry to one day, in place, and return it."""
    for target in entry["targets"].values():
        target["verified_on"] = day
        for source in target["sources"]:
            source["read_on"] = day
        if "last_release_on" in target:
            target["last_release_on"] = day
    return entry


@pytest.mark.parametrize(
    ("today", "expected"),
    [
        (date(2027, 2, 14), None),
        (date(2027, 2, 15), Severity.WARNING),
        (date(2027, 3, 14), Severity.WARNING),
        (date(2027, 3, 15), Severity.ERROR),
    ],
)
def test_each_source_expires_six_months_after_its_own_reading(
    today: date,
    expected: Severity | None,
    minimal_entry: dict[str, Any],
    write_entry: WriteEntry,
    settings: Settings,
) -> None:
    # verified_on stays recent because another source was read on 2027-01-01:
    # the old source must still expire on its own (2026-09-15 + 6 months).
    # Dates stay after those of accepted-licenses.yaml, never in its future.
    entry = dated(minimal_entry, "2027-01-01")
    entry["targets"]["local"]["sources"].append(
        {"url": "https://example.invalid/oss/old", "read_on": "2026-09-15"}
    )

    findings = check_on(today, write_entry(entry), settings)

    stale = [
        f.severity
        for f in findings
        if (f.path, f.rule) == ("targets/local/sources/1/read_on", "stale-source")
    ]
    assert stale == ([expected] if expected else [])
    assert rules_of(findings, Severity.ERROR) == (
        [("targets/local/sources/1/read_on", "stale-source")] if expected is Severity.ERROR else []
    )
