"""A cloud target that lists a managed and a self-hosted option (ADR-009, 2026-11-26)."""

from __future__ import annotations

import copy
from collections.abc import Callable
from dataclasses import replace
from datetime import date
from pathlib import Path
from typing import Any

from catalog_findings import Finding, Severity
from check_catalog import Settings, run_check

WriteEntry = Callable[..., Path]

MANAGED_FIELDS = {
    "choose_when": "Choisir le service managé quand l'équipe ne veut pas exploiter la brique.",
    "validation": "covered",
    "offered": True,
}
OSS_FIELDS = {
    "choose_when": "Choisir le composant libre quand la portabilité compte plus que l'exploitation.",
    "validation": "not-covered",
    "offered": False,
}


def with_two_cloud_options(entry: dict[str, Any]) -> dict[str, Any]:
    """The minimal entry, with gcp as a list: its managed target, then a copy of local."""
    managed = {**entry["targets"]["gcp"], **MANAGED_FIELDS}
    oss = {**copy.deepcopy(entry["targets"]["local"]), **OSS_FIELDS}
    return {**entry, "targets": {**entry["targets"], "gcp": [managed, oss]}}


def check_on(day: date, path: Path, settings: Settings) -> list[Finding]:
    return run_check([path], replace(settings, today=day))


def errors(findings: list[Finding]) -> list[tuple[str, str]]:
    return [(f.path, f.rule) for f in findings if f.severity is Severity.ERROR]


def warnings(findings: list[Finding]) -> list[tuple[str, str]]:
    return [(f.path, f.rule) for f in findings if f.severity is Severity.WARNING]


def test_two_cloud_options_pass(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    entry = with_two_cloud_options(minimal_entry)

    findings = run_check([write_entry(entry)], settings)

    assert errors(findings) == []


def test_each_cloud_option_is_checked_at_its_own_path(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    entry = with_two_cloud_options(minimal_entry)
    entry["targets"]["gcp"][1]["verified_on"] = "2026-11-20"
    entry["targets"]["gcp"][1]["sources"][0]["read_on"] = "2026-11-20"
    entry["targets"]["gcp"][1]["status"] = "archived"

    findings = check_on(date(2026, 11, 21), write_entry(entry), settings)

    assert errors(findings) == [("targets/gcp/1/status", "status")]


def test_stale_second_option_fails_on_its_own_date(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    entry = with_two_cloud_options(minimal_entry)
    entry["targets"]["gcp"][0]["verified_on"] = "2026-11-20"
    entry["targets"]["gcp"][0]["sources"][0]["read_on"] = "2026-11-20"

    findings = check_on(date(2027, 5, 19), write_entry(entry), settings)

    assert ("targets/gcp/1/verified_on", "stale-verification") in errors(findings)
    assert ("targets/gcp/0/verified_on", "stale-verification") not in errors(findings)


def test_standards_warning_counts_the_standards_of_every_option(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    entry = with_two_cloud_options(minimal_entry)
    entry["targets"]["local"]["standards"] = ["gateway-api"]
    entry["targets"]["gcp"][1]["standards"] = ["gateway-api"]

    findings = run_check([write_entry(entry)], settings)

    assert ("targets", "standards") not in warnings(findings)


def test_standards_warning_stays_when_no_option_shares_one(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    entry = with_two_cloud_options(minimal_entry)
    entry["targets"]["local"]["standards"] = ["gateway-api"]

    findings = run_check([write_entry(entry)], settings)

    assert ("targets", "standards") in warnings(findings)


def test_pending_item_of_an_option_is_listed_at_its_path(
    minimal_entry: dict[str, Any], write_entry: WriteEntry, settings: Settings
) -> None:
    entry = with_two_cloud_options(minimal_entry)
    entry["targets"]["gcp"][1]["pending"] = [
        {"topic": "validation", "owner": "QA", "note": "Matrice à étendre."}
    ]

    findings = run_check([write_entry(entry)], settings)

    assert ("targets/gcp/1/pending", "pending") in warnings(findings)
