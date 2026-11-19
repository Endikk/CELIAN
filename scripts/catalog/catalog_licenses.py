"""Match a license expression against accepted-licenses.yaml, next to this file.

The allowlist is written by CELIAN: SPDX identifiers whose approval was read
on opensource.org, with the date of reading. An identifier outside the list is
an error, whatever the operator (AND, OR): a dual license with a branch the
list does not hold is flagged too, and settled by an ADR and a PR reviewed by
[SECU] if it must stay. The identifier after WITH must be an accepted
exception. A license marked network_copyleft passes with a warning.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from types import MappingProxyType
from typing import Any

from catalog_findings import Finding, error, has_errors
from catalog_schema import DIALECT, build_validator, validate_entry
from catalog_yaml import load_entry, trailing_newline_findings

RULE = "license-list"
DATE_PATTERN = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
ALLOWLIST_SCHEMA: Mapping[str, Any] = {
    "$schema": DIALECT,
    "type": "object",
    "additionalProperties": False,
    "required": ["licenses", "exceptions"],
    "properties": {
        "licenses": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/license"}},
        "exceptions": {"type": "array", "items": {"$ref": "#/$defs/exception"}},
    },
    "$defs": {
        "spdxId": {"type": "string", "maxLength": 64, "pattern": "^[A-Za-z0-9][A-Za-z0-9.+-]*$"},
        "date": {"type": "string", "format": "date", "maxLength": 10, "pattern": DATE_PATTERN},
        "note": {"type": "string", "minLength": 1, "maxLength": 500},
        "license": {
            "type": "object",
            "additionalProperties": False,
            "required": ["id", "osi_page", "read_on"],
            "properties": {
                "id": {"$ref": "#/$defs/spdxId"},
                "osi_page": {
                    "type": "string",
                    "maxLength": 200,
                    "pattern": "^https://opensource\\.org/license/[a-z0-9-]+$",
                },
                "read_on": {"$ref": "#/$defs/date"},
                "network_copyleft": {"type": "boolean"},
                "note": {"$ref": "#/$defs/note"},
            },
        },
        "exception": {
            "type": "object",
            "additionalProperties": False,
            "required": ["id", "source", "read_on"],
            "properties": {
                "id": {"$ref": "#/$defs/spdxId"},
                "source": {"type": "string", "maxLength": 300, "pattern": "^https://[^\\s]+$"},
                "read_on": {"$ref": "#/$defs/date"},
                "note": {"$ref": "#/$defs/note"},
            },
        },
    },
}


@dataclass(frozen=True)
class AcceptedLicense:
    spdx_id: str
    network_copyleft: bool


@dataclass(frozen=True)
class AcceptedLicenses:
    """Licenses and exceptions, keyed by lower-case identifier."""

    licenses: Mapping[str, AcceptedLicense]
    exceptions: Mapping[str, AcceptedLicense]


@dataclass(frozen=True)
class LoadedLicenses:
    licenses: AcceptedLicenses | None
    findings: tuple[Finding, ...]


def load_accepted_licenses(path: Path, shown: str, today: date) -> LoadedLicenses:
    loaded = load_entry(path, shown)
    if loaded.findings:
        return LoadedLicenses(None, loaded.findings)
    validator = build_validator(ALLOWLIST_SCHEMA)
    findings = (
        *trailing_newline_findings(loaded.data, shown),
        *validate_entry(validator, loaded.data, shown, prefix=RULE),
    )
    if not findings:
        findings = _list_findings(loaded.data, shown, today)
    if has_errors(findings):
        return LoadedLicenses(None, tuple(findings))
    return LoadedLicenses(_accepted(loaded.data), ())


def license_problems(expression: str, accepted: AcceptedLicenses) -> list[str]:
    """Problems of each identifier in an expression without parentheses.

    The schema pattern already guarantees the shape: identifiers separated by
    AND, OR or WITH. The identifier after WITH is an exception.
    """
    return [
        problem
        for token, is_exception in _identifiers(expression)
        for problem in _identifier_problems(token, is_exception, accepted)
    ]


def network_copyleft(expression: str, accepted: AcceptedLicenses) -> list[str]:
    """Identifiers of the expression that the allowlist marks network_copyleft."""
    return [
        token
        for token, is_exception in _identifiers(expression)
        if not is_exception
        and (known := accepted.licenses.get(token.lower())) is not None
        and known.network_copyleft
    ]


def _identifiers(expression: str) -> list[tuple[str, bool]]:
    tokens = expression.split(" ")
    return [
        (tokens[index], index > 0 and tokens[index - 1] == "WITH")
        for index in range(0, len(tokens), 2)
    ]


def _identifier_problems(token: str, is_exception: bool, accepted: AcceptedLicenses) -> list[str]:
    table = accepted.exceptions if is_exception else accepted.licenses
    known = table.get(token.lower())
    if known is None:
        kind = "an exception of" if is_exception else "in"
        return [
            f"{token!r} is not {kind} the CELIAN license allowlist: "
            "adding one takes a PR reviewed by [SECU]"
        ]
    if known.spdx_id != token:
        return [f"{token!r} is written {known.spdx_id!r} in the CELIAN license allowlist"]
    return []


def _list_findings(data: Mapping[str, Any], shown: str, today: date) -> tuple[Finding, ...]:
    """Ids unique without regard to case, and no reading date after today."""
    findings: list[Finding] = []
    for group in ("licenses", "exceptions"):
        seen: set[str] = set()
        for index, item in enumerate(data[group]):
            key = item["id"].lower()
            if key in seen:
                message = f"{item['id']!r} is listed twice"
                findings.append(error(shown, f"{group}/{index}/id", RULE, message))
            seen.add(key)
            if date.fromisoformat(item["read_on"]) > today:
                message = f"{item['read_on']} is after today, {today} (UTC)"
                findings.append(error(shown, f"{group}/{index}/read_on", RULE, message))
    return tuple(findings)


def _accepted(data: Mapping[str, Any]) -> AcceptedLicenses:
    def table(group: str) -> Mapping[str, AcceptedLicense]:
        return MappingProxyType(
            {
                item["id"].lower(): AcceptedLicense(item["id"], item.get("network_copyleft", False))
                for item in data[group]
            }
        )

    return AcceptedLicenses(table("licenses"), table("exceptions"))
