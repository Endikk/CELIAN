"""Rules of ADR-009 that JSON Schema cannot express.

They run on entries that passed the schema, so the shape is known: every key
the schema requires is present and every date is a real YYYY-MM-DD string.
The rules that need no shape (trailing line breaks) live in catalog_yaml.py.
"""

from __future__ import annotations

import calendar
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

from catalog_findings import Finding, error, json_path, warning
from catalog_licenses import AcceptedLicenses, license_problems, network_copyleft

VERIFICATION_MONTHS = 6
WARNING_MONTHS = VERIFICATION_MONTHS - 1
RELEASE_MONTHS = 12
DECISION_FOLDERS = {"adr": "adr", "bench": "benchmarks"}
STANDARDS_MESSAGE = (
    "local and gcp share no standard: the target layer carries the whole difference (principle II)"
)
NETWORK_COPYLEFT_MESSAGE = (
    "{!r} is a network copyleft license: a modified version must offer its source to the "
    "users who interact with it over a network; the ADR of the brick says how the generated "
    "project complies"
)

PathParts = tuple[str | int, ...]


@dataclass(frozen=True)
class RuleContext:
    today: date
    docs_dir: Path
    licenses: AcceptedLicenses


def add_months(start: date, months: int) -> date:
    """Same day number, months later; the last day when that day does not exist."""
    index = start.month - 1 + months
    year, month = start.year + index // 12, index % 12 + 1
    return date(year, month, min(start.day, calendar.monthrange(year, month)[1]))


def entry_findings(
    data: Mapping[str, Any], path: Path, shown: str, ctx: RuleContext
) -> list[Finding]:
    targets = data["targets"]
    return [
        *_file_name_findings(data["id"], path, shown),
        *(
            finding
            for name, target in targets.items()
            for finding in _target_findings(target, ("targets", name), shown, ctx)
        ),
        *_standards_findings(targets, shown),
    ]


def duplicate_id_findings(entries: list[tuple[str, str]]) -> list[Finding]:
    """entries: (shown file, id) of every entry that passed the schema."""
    first_file: dict[str, str] = {}
    findings: list[Finding] = []
    for shown, entry_id in entries:
        if entry_id in first_file:
            message = f"id {entry_id!r} is already used by {first_file[entry_id]}"
            findings.append(error(shown, "id", "duplicate-id", message))
        else:
            first_file[entry_id] = shown
    return findings


def _file_name_findings(entry_id: str, path: Path, shown: str) -> list[Finding]:
    if path.name == f"{entry_id}.yaml":
        return []
    message = (
        f"id {entry_id!r} does not match the file name {path.name!r}: expected {entry_id}.yaml"
    )
    return [error(shown, "id", "file-name", message)]


def _target_findings(
    target: Mapping[str, Any], parts: PathParts, shown: str, ctx: RuleContext
) -> list[Finding]:
    return [
        *_future_date_findings(target, parts, shown, ctx.today),
        *_verification_findings(target, parts, shown, ctx.today),
        *_release_findings(target, parts, shown, ctx.today),
        *_status_findings(target, parts, shown),
        *_decision_findings(target["decisions"], (*parts, "decisions"), shown, ctx.docs_dir),
        *_license_findings(target, parts, shown, ctx.licenses),
        *_artifact_findings(target.get("artifacts", []), (*parts, "artifacts"), shown),
        *_pending_findings(target.get("pending", []), (*parts, "pending"), shown),
    ]


def _dated_fields(target: Mapping[str, Any], parts: PathParts) -> Iterator[tuple[PathParts, str]]:
    for key in ("last_release_on", "verified_on"):
        if key in target:
            yield (*parts, key), target[key]
    for group in ("sources", "artifacts"):
        for index, item in enumerate(target.get(group, [])):
            yield (*parts, group, index, "read_on"), item["read_on"]


def _future_date_findings(
    target: Mapping[str, Any], parts: PathParts, shown: str, today: date
) -> list[Finding]:
    return [
        error(shown, json_path(where), "future-date", f"{value} is after today, {today} (UTC)")
        for where, value in _dated_fields(target, parts)
        if date.fromisoformat(value) > today
    ]


@dataclass(frozen=True)
class Dated:
    """A date that expires six calendar months later, and how to name it."""

    day: date
    where: str
    rule: str
    what: str
    action: str


def _verification_findings(
    target: Mapping[str, Any], parts: PathParts, shown: str, today: date
) -> list[Finding]:
    """verified_on equals the latest read_on, and nothing is six months old.

    Each source expires on its own: moving verified_on after reading a single
    source again does not renew the others ([SECU] review, S4).
    """
    verified = date.fromisoformat(target["verified_on"])
    latest = max(date.fromisoformat(source["read_on"]) for source in target["sources"])
    where = json_path((*parts, "verified_on"))
    findings: list[Finding] = []
    if verified != latest:
        message = (
            f"verified_on is {verified} but the most recent read_on of the sources is {latest}: "
            "they must be equal"
        )
        findings.append(error(shown, where, "verified-on", message))
    dated = [
        Dated(
            verified, where, "stale-verification", f"verified on {verified}", "re-read the sources"
        ),
        *(
            Dated(
                date.fromisoformat(source["read_on"]),
                json_path((*parts, "sources", index, "read_on")),
                "stale-source",
                f"source read on {source['read_on']}",
                "re-read it",
            )
            for index, source in enumerate(target["sources"])
        ),
    ]
    return [*findings, *(f for item in dated for f in _expiry_findings(item, today, shown))]


def _expiry_findings(item: Dated, today: date, shown: str) -> list[Finding]:
    """Error from six calendar months after the date, warning during the last month."""
    deadline = add_months(item.day, VERIFICATION_MONTHS)
    if today >= deadline:
        message = (
            f"{item.what}, expired on {deadline} (six calendar months): "
            f"{item.action}, then update read_on and verified_on"
        )
        return [error(shown, item.where, item.rule, message)]
    if today >= add_months(item.day, WARNING_MONTHS):
        message = (
            f"{item.what}, expires on {deadline} (six calendar months): {item.action} before then"
        )
        return [warning(shown, item.where, item.rule, message)]
    return []


def _release_findings(
    target: Mapping[str, Any], parts: PathParts, shown: str, today: date
) -> list[Finding]:
    if "last_release_on" not in target:
        return []
    released = date.fromisoformat(target["last_release_on"])
    limit = add_months(released, RELEASE_MONTHS)
    if today < limit:
        return []
    message = (
        f"no upstream release since {released}: "
        f"the twelve-month limit of principle VI was reached on {limit}"
    )
    return [error(shown, json_path((*parts, "last_release_on")), "release-age", message)]


def _status_findings(target: Mapping[str, Any], parts: PathParts, shown: str) -> list[Finding]:
    status = target["status"]
    if status == "active":
        return []
    message = f"status is {status!r}: only 'active' may stay in the catalog (principle VI)"
    return [error(shown, json_path((*parts, "status")), "status", message)]


def _decision_findings(
    decisions: Mapping[str, list[str]], parts: PathParts, shown: str, docs_dir: Path
) -> list[Finding]:
    findings: list[Finding] = []
    for kind, folder in DECISION_FOLDERS.items():
        for index, ref in enumerate(decisions.get(kind, [])):
            if not any((docs_dir / folder).glob(f"{ref}-*.md")):
                message = f"{ref} not found: no docs/{folder}/{ref}-*.md file"
                findings.append(
                    error(shown, json_path((*parts, kind, index)), "decision-link", message)
                )
    return findings


def _license_findings(
    target: Mapping[str, Any], parts: PathParts, shown: str, licenses: AcceptedLicenses
) -> list[Finding]:
    if "license" not in target:
        return []
    where = json_path((*parts, "license"))
    expression = target["license"]
    return [
        *(
            error(shown, where, "license", problem)
            for problem in license_problems(expression, licenses)
        ),
        *(
            warning(shown, where, "network-copyleft", NETWORK_COPYLEFT_MESSAGE.format(spdx_id))
            for spdx_id in network_copyleft(expression, licenses)
        ),
    ]


def _artifact_findings(
    artifacts: list[Mapping[str, Any]], parts: PathParts, shown: str
) -> list[Finding]:
    first_index: dict[str, int] = {}
    findings: list[Finding] = []
    for index, artifact in enumerate(artifacts):
        platform = artifact["platform"]
        if platform in first_index:
            message = (
                f"second digest for {platform}: artifacts/{first_index[platform]} already has one"
            )
            findings.append(
                error(shown, json_path((*parts, index, "platform")), "artifact-platform", message)
            )
        else:
            first_index[platform] = index
    return findings


def _pending_findings(
    pending: list[Mapping[str, str]], parts: PathParts, shown: str
) -> list[Finding]:
    if not pending:
        return []
    topics = ", ".join(f"{item['topic']} ({item['owner']})" for item in pending)
    message = (
        f"{len(pending)} open item(s), {topics}: "
        "no blueprint may use this target yet (principle IV)"
    )
    return [warning(shown, json_path(parts), "pending", message)]


def _standards_findings(targets: Mapping[str, Mapping[str, Any]], shown: str) -> list[Finding]:
    shared = set.intersection(*(set(target["standards"]) for target in targets.values()))
    if shared:
        return []
    return [warning(shown, "targets", "standards", STANDARDS_MESSAGE)]
