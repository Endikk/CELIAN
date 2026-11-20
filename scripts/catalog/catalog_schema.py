"""Load the catalog schema safely, then validate entries against it.

Three things python-jsonschema does not do by default, and that the catalog
needs (ADR-001, ADR-009):

- format is only an annotation in 2020-12: a format checker is passed, and
  every format the schema uses must have a checker installed, or the check
  stops instead of skipping it silently;
- the default registry retrieves remote references over the network: an
  empty registry is passed, so only the bundled meta-schemas resolve, and
  any $ref that leaves the schema file is refused before validation;
- check_schema stops at the first meta-schema error: all of them are listed.
"""

from __future__ import annotations

import json
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

import referencing
from catalog_findings import ROOT_PATH, Finding, error, json_path
from jsonschema import Draft202012Validator, ValidationError

DIALECT = Draft202012Validator.META_SCHEMA["$id"]
FORMAT_CHECKER = Draft202012Validator.FORMAT_CHECKER
REFERENCE_KEYWORDS = ("$ref", "$dynamicRef")
MAX_MESSAGE = 300

PathParts = tuple[str | int, ...]


@dataclass(frozen=True)
class LoadedSchema:
    """A validator ready for entries, or the findings that make it unusable."""

    validator: Draft202012Validator | None
    findings: tuple[Finding, ...]


def build_validator(schema: Mapping[str, Any]) -> Draft202012Validator:
    """A 2020-12 validator that checks formats and never leaves the process."""
    return Draft202012Validator(
        schema, format_checker=FORMAT_CHECKER, registry=referencing.Registry()
    )


def load_schema(path: Path, shown: str) -> LoadedSchema:
    try:
        schema = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return LoadedSchema(None, (error(shown, ROOT_PATH, "schema-file", str(exc)),))
    findings = schema_findings(schema, shown)
    if findings:
        return LoadedSchema(None, findings)
    return LoadedSchema(build_validator(schema), ())


def schema_findings(schema: object, shown: str) -> tuple[Finding, ...]:
    if not isinstance(schema, dict) or schema.get("$schema") != DIALECT:
        message = f'the schema must declare "$schema": "{DIALECT}" (ADR-001)'
        return (error(shown, "$schema", "schema-dialect", message),)
    meta = build_validator(Draft202012Validator.META_SCHEMA)
    return (
        *(_finding(shown, "metaschema", e) for e in _sorted(meta.iter_errors(schema))),
        *_remote_reference_findings(schema, shown),
        *_format_findings(schema, shown),
    )


def validate_entry(
    validator: Draft202012Validator, data: object, shown: str, prefix: str = "schema"
) -> tuple[Finding, ...]:
    return tuple(_finding(shown, prefix, e) for e in _sorted(validator.iter_errors(data)))


def _sorted(errors: Iterator[ValidationError]) -> list[ValidationError]:
    return sorted(errors, key=lambda e: (json_path(e.absolute_path), str(e.validator), e.message))


def _finding(shown: str, prefix: str, exc: ValidationError) -> Finding:
    rule = f"{prefix}:{exc.validator}"
    return error(shown, json_path(exc.absolute_path), rule, _message(exc))


def _message(exc: ValidationError) -> str:
    if exc.validator == "type" and isinstance(exc.instance, date):
        day = exc.instance.isoformat()[:10]
        return f'unquoted date {day}: write it as a quoted string, "{day}"'
    if exc.validator == "not" and isinstance(exc.validator_value, Mapping):
        forbidden = exc.validator_value.get("required", [])
        if forbidden:
            return f"{', '.join(map(repr, forbidden))} is not allowed here"
    message = exc.message
    return message if len(message) <= MAX_MESSAGE else message[: MAX_MESSAGE - 3] + "..."


def _walk(node: object, parts: PathParts = ()) -> Iterator[tuple[PathParts, str, object]]:
    """Yield (path, key, value) for every key of every object in a JSON value."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield parts, key, value
            yield from _walk(value, (*parts, key))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            yield from _walk(item, (*parts, index))


def _remote_reference_findings(schema: object, shown: str) -> Iterator[Finding]:
    for parts, key, value in _walk(schema):
        if key in REFERENCE_KEYWORDS and isinstance(value, str) and not value.startswith("#"):
            message = f"{value!r} leaves the schema file: only local references (#...) are allowed"
            yield error(shown, json_path((*parts, key)), "schema-remote-ref", message)


def _format_findings(schema: object, shown: str) -> Iterator[Finding]:
    for parts, key, value in _walk(schema):
        if key == "format" and isinstance(value, str) and value not in FORMAT_CHECKER.checkers:
            message = f"no checker installed for format {value!r}: it would be skipped silently"
            yield error(shown, json_path((*parts, key)), "schema-format", message)
