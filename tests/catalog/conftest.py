"""Fixtures shared by the catalog check tests."""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
import yaml
from catalog_testing import MINIMAL, TODAY
from check_catalog import Settings


@pytest.fixture
def settings() -> Settings:
    """Repository schema, docs and license allowlist, with today injected."""
    return Settings.defaults(today=TODAY)


@pytest.fixture
def minimal_entry() -> dict[str, Any]:
    """A fresh copy of the minimal valid entry: each test gets its own."""
    data: dict[str, Any] = yaml.safe_load(MINIMAL.read_text(encoding="utf-8"))
    return data


@pytest.fixture
def write_entry(tmp_path: Path) -> Callable[..., Path]:
    """Write an entry as <id>.yaml, or under an explicit name, in tmp_path."""

    def write(data: dict[str, Any], name: str | None = None) -> Path:
        path = tmp_path / (name or f"{data['id']}.yaml")
        path.parent.mkdir(parents=True, exist_ok=True)
        text = yaml.safe_dump(data, sort_keys=False, allow_unicode=True)
        path.write_text(text, encoding="utf-8")
        return path

    return write
