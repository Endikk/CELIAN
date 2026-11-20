"""Read a catalog entry with yaml.safe_load, after a structural pass.

PyYAML keeps the last value of a duplicate key without a word (ADR-009). The
file is therefore composed first, without building any Python object, and the
node tree is checked for duplicate keys. Aliases and merge keys are refused in
the same pass: a merge can hide a duplicate, and aliases can make a small
file expand into a huge document. Only then does yaml.safe_load build the
data (ADR-001, condition 1).
"""

from __future__ import annotations

from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from catalog_findings import ROOT_PATH, Finding, error, json_path

MERGE_TAG = "tag:yaml.org,2002:merge"
ALIAS_MESSAGE = "anchors and aliases are not allowed in catalog entries"
MERGE_MESSAGE = "merge keys (<<) are not allowed in catalog entries"
NEWLINE_MESSAGE = (
    'the string ends with a line break: write it on one line, or end the block with ">-" or "|-"'
)

PathParts = tuple[str | int, ...]
Located = tuple[yaml.Node, PathParts]


@dataclass(frozen=True)
class LoadedEntry:
    """The data of a file, or the findings that kept it from being read."""

    data: Any
    findings: tuple[Finding, ...]


def load_entry(path: Path, shown: str) -> LoadedEntry:
    try:
        text = path.read_bytes().decode("utf-8")
    except OSError as exc:
        return _refused(shown, "file-read", exc.strerror or str(exc))
    except UnicodeDecodeError as exc:
        return _refused(shown, "file-encoding", f"not UTF-8: {exc.reason} at byte {exc.start}")
    try:
        root = yaml.compose(text, Loader=yaml.SafeLoader)
    except yaml.YAMLError as exc:
        return _refused(shown, "yaml-syntax", _one_line(exc))
    findings = structure_findings(root, shown)
    if findings:
        return LoadedEntry(None, findings)
    try:
        return LoadedEntry(yaml.safe_load(text), ())
    except yaml.YAMLError as exc:
        return _refused(shown, "yaml-syntax", _one_line(exc))


def structure_findings(root: yaml.Node | None, shown: str) -> tuple[Finding, ...]:
    """Walk the node tree in document order, without recursion."""
    findings: list[Finding] = []
    seen: set[int] = set()
    stack: list[Located] = [(root, ())] if root is not None else []
    while stack:
        node, parts = stack.pop()
        if id(node) in seen:
            findings.append(error(shown, json_path(parts), "yaml-alias", ALIAS_MESSAGE))
            continue
        seen.add(id(node))
        children, problems = _children(node, parts, shown)
        findings.extend(problems)
        stack.extend(reversed(children))
    return tuple(findings)


def _children(node: yaml.Node, parts: PathParts, shown: str) -> tuple[list[Located], list[Finding]]:
    if isinstance(node, yaml.SequenceNode):
        return [(item, (*parts, index)) for index, item in enumerate(node.value)], []
    if isinstance(node, yaml.MappingNode):
        return _mapping_children(node, parts, shown)
    return [], []


def _mapping_children(
    node: yaml.MappingNode, parts: PathParts, shown: str
) -> tuple[list[Located], list[Finding]]:
    children: list[Located] = []
    problems: list[Finding] = []
    first_lines: dict[str, int] = {}
    for key_node, value_node in node.value:
        key = str(key_node.value) if isinstance(key_node, yaml.ScalarNode) else "?"
        line = key_node.start_mark.line + 1
        here = json_path((*parts, key))
        if key_node.tag == MERGE_TAG:
            problems.append(error(shown, here, "yaml-merge-key", MERGE_MESSAGE))
        elif key in first_lines:
            message = f"duplicate key {key!r} on line {line}, first on line {first_lines[key]}"
            problems.append(error(shown, here, "duplicate-key", message))
        elif isinstance(key_node, yaml.ScalarNode):
            first_lines[key] = line
        children.append((value_node, (*parts, key)))
    return children, problems


def _refused(shown: str, rule: str, message: str) -> LoadedEntry:
    return LoadedEntry(None, (error(shown, ROOT_PATH, rule, message),))


def _one_line(exc: yaml.YAMLError) -> str:
    return " ".join(str(exc).split())


def trailing_newline_findings(node: object, shown: str, parts: PathParts = ()) -> Iterator[Finding]:
    """Strings that end with a line break, anywhere in loaded data.

    The schema pattern cannot catch them: python-jsonschema evaluates pattern
    with re.search, and "$" also matches just before a final newline.
    """
    if isinstance(node, str) and node.endswith(("\n", "\r")):
        yield error(shown, json_path(parts), "trailing-newline", NEWLINE_MESSAGE)
    elif isinstance(node, Mapping):
        for key, value in node.items():
            yield from trailing_newline_findings(value, shown, (*parts, str(key)))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            yield from trailing_newline_findings(item, shown, (*parts, index))
