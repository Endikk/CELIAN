"""Paths and the injected date shared by the catalog check tests.

The check lives in scripts/catalog/, outside any package: importing this
module puts that folder on the import path, once, for every test here.
"""

from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts" / "catalog"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

TODAY = date(2026, 11, 19)
TESTS_DIR = Path(__file__).parent
VALID_DIR = TESTS_DIR / "valid"
INVALID_DIR = TESTS_DIR / "invalid"
CATALOG_DIR = REPO_ROOT / "catalog"
MINIMAL = VALID_DIR / "minimal.yaml"
