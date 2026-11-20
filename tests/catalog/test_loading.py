"""YAML reading and schema loading: what must stop before any rule runs."""

from __future__ import annotations

import json
import urllib.request
from dataclasses import replace
from pathlib import Path
from typing import Any

import pytest
import referencing.exceptions
from catalog_findings import Finding, Severity
from catalog_schema import build_validator
from catalog_testing import MINIMAL, REPO_ROOT
from check_catalog import Settings, run_check
from jsonschema import Draft202012Validator

SCHEMA = REPO_ROOT / "schema" / "catalog-entry.schema.json"
REMOTE_REF_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$ref": "https://example.invalid/remote.json",
}


def errors_of(findings: list[Finding]) -> list[tuple[str, str]]:
    return [(f.path, f.rule) for f in findings if f.severity is Severity.ERROR]


def write_text(tmp_path: Path, text: str, name: str = "minimal.yaml") -> Path:
    path = tmp_path / name
    path.write_text(text, encoding="utf-8")
    return path


def minimal_text() -> str:
    return MINIMAL.read_text(encoding="utf-8")


def test_duplicate_key_is_refused_with_both_lines(tmp_path: Path, settings: Settings) -> None:
    text = minimal_text().replace(
        "    license: Apache-2.0\n",
        "    license: Apache-2.0\n    license: MIT\n",
    )

    findings = run_check([write_text(tmp_path, text)], settings)

    assert errors_of(findings) == [("targets/local/license", "duplicate-key")]
    assert findings[0].message == "duplicate key 'license' on line 15, first on line 14"


def test_alias_is_refused(tmp_path: Path, settings: Settings) -> None:
    text = (
        minimal_text()
        .replace("summary: Brique fictive", "summary: &summary Brique fictive")
        .replace("    service: Example OSS\n", "    service: *summary\n")
    )

    findings = run_check([write_text(tmp_path, text)], settings)

    assert errors_of(findings) == [("targets/local/service", "yaml-alias")]


def test_merge_key_is_refused(tmp_path: Path, settings: Settings) -> None:
    text = minimal_text().replace("    type: oss\n", "    <<: {license: MIT}\n    type: oss\n")

    findings = run_check([write_text(tmp_path, text)], settings)

    assert errors_of(findings) == [("targets/local/<<", "yaml-merge-key")]


@pytest.mark.parametrize(
    "text",
    [
        "id: [unclosed\n",
        "id: minimal\n---\nid: second\n",
        "id: !!python/object/apply:os.system ['true']\n",
    ],
    ids=["syntax", "two-documents", "python-tag"],
)
def test_yaml_outside_the_safe_subset_is_refused(
    text: str, tmp_path: Path, settings: Settings
) -> None:
    findings = run_check([write_text(tmp_path, text)], settings)

    assert errors_of(findings) == [("(root)", "yaml-syntax")]


def test_python_tag_is_never_constructed(tmp_path: Path, settings: Settings) -> None:
    marker = tmp_path / "constructed"
    text = (
        "id: !!python/object/apply:pathlib.Path.touch\n"
        f"  - !!python/object/apply:pathlib.Path ['{marker}']\n"
    )

    findings = run_check([write_text(tmp_path, text)], settings)

    assert errors_of(findings) == [("(root)", "yaml-syntax")]
    assert not marker.exists()


def test_binary_value_fails_the_schema(tmp_path: Path, settings: Settings) -> None:
    text = minimal_text().replace("id: minimal", "id: !!binary bWluaW1hbA==")

    findings = run_check([write_text(tmp_path, text)], settings)

    assert errors_of(findings) == [("id", "schema:type")]


def test_file_that_is_not_utf8_is_refused(tmp_path: Path, settings: Settings) -> None:
    path = tmp_path / "minimal.yaml"
    path.write_bytes(minimal_text().encode("utf-16"))

    findings = run_check([path], settings)

    assert errors_of(findings) == [("(root)", "file-encoding")]


def write_schema(tmp_path: Path, change: dict[str, Any]) -> Path:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    path = tmp_path / "schema.json"
    path.write_text(json.dumps({**schema, **change}), encoding="utf-8")
    return path


@pytest.mark.parametrize(
    ("change", "expected"),
    [
        ({"$schema": "http://json-schema.org/draft-07/schema#"}, ("$schema", "schema-dialect")),
        ({"type": 12}, ("type", "metaschema:anyOf")),
        (
            {"properties": {"id": {"$ref": "https://example.invalid/id.json"}}},
            ("properties/id/$ref", "schema-remote-ref"),
        ),
        (
            {"properties": {"id": {"type": "string", "format": "uri"}}},
            ("properties/id/format", "schema-format"),
        ),
    ],
    ids=["dialect", "metaschema", "remote-ref", "format-without-checker"],
)
def test_schema_problem_stops_the_check(
    change: dict[str, Any], expected: tuple[str, str], tmp_path: Path, settings: Settings
) -> None:
    broken = replace(settings, schema_path=write_schema(tmp_path, change))

    findings = run_check([MINIMAL], broken)

    assert errors_of(findings) == [expected]
    assert Path(findings[0].file).name == "schema.json"


def test_validator_never_fetches_a_remote_reference(monkeypatch: pytest.MonkeyPatch) -> None:
    opened: list[object] = []

    def fake_urlopen(request: object, *args: object, **kwargs: object) -> None:
        opened.append(request)
        raise OSError("network disabled in this test")

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    # Control: python-jsonschema's default registry does try the network.
    with pytest.raises(referencing.exceptions.Unresolvable):
        list(Draft202012Validator(REMOTE_REF_SCHEMA).iter_errors({}))
    assert len(opened) == 1

    with pytest.raises(referencing.exceptions.Unresolvable):
        list(build_validator(REMOTE_REF_SCHEMA).iter_errors({}))
    assert len(opened) == 1


def test_schema_pattern_lets_a_final_newline_through() -> None:
    # Why the trailing-newline rule exists: python-jsonschema evaluates
    # pattern with re.search, and "$" matches before a final "\n".
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    line200 = {"$schema": schema["$schema"], **schema["$defs"]["line200"]}
    validator = build_validator(line200)

    assert list(validator.iter_errors("Une ligne.\n")) == []
    assert list(validator.iter_errors("Une ligne.\nUne autre.")) != []


def test_missing_file_is_reported(tmp_path: Path, settings: Settings) -> None:
    findings = run_check([tmp_path / "absent.yaml"], settings)

    assert errors_of(findings) == [("(root)", "file-read")]


def test_unreadable_schema_stops_the_check(tmp_path: Path, settings: Settings) -> None:
    schema = write_text(tmp_path, "{not json", name="schema.json")

    findings = run_check([MINIMAL], replace(settings, schema_path=schema))

    assert errors_of(findings) == [("(root)", "schema-file")]


def test_long_schema_message_is_shortened(tmp_path: Path, settings: Settings) -> None:
    text = minimal_text().replace(
        "    status: active\n", f"    status: active\n    notes: {'n' * 600}\n", 1
    )

    findings = run_check([write_text(tmp_path, text)], settings)

    assert errors_of(findings) == [("targets/local/notes", "schema:maxLength")]
    assert len(findings[0].message) == 300
    assert findings[0].message.endswith("...")
