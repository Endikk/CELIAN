"""Symbolic links are refused without being followed (catalog/ and arguments)."""

from __future__ import annotations

from pathlib import Path

import pytest
from catalog_findings import Finding, Severity
from catalog_testing import MINIMAL
from check_catalog import Settings, main, run_check

MARKER = "celian-test-marker-0123456789"


@pytest.fixture
def secret_file(tmp_path: Path) -> Path:
    """A file outside any catalog folder, as a file under ~/.ssh would be."""
    outside = tmp_path / "outside"
    outside.mkdir()
    path = outside / "id_test"
    path.write_text(f"key: [{MARKER}\n", encoding="utf-8")
    return path


def assert_nothing_leaks(findings: list[Finding], secret_file: Path) -> None:
    for finding in findings:
        text = finding.render()
        assert MARKER not in text
        assert secret_file.name not in text
        assert "outside" not in text


def test_link_inside_the_catalog_folder_is_refused(
    tmp_path: Path, secret_file: Path, settings: Settings
) -> None:
    folder = tmp_path / "catalog"
    folder.mkdir()
    (folder / "minimal.yaml").symlink_to(secret_file)

    findings = run_check([folder], settings)

    assert [(Path(f.file).name, f.rule) for f in findings] == [("minimal.yaml", "symlink")]
    assert_nothing_leaks(findings, secret_file)


def test_link_given_as_argument_is_refused(
    tmp_path: Path, secret_file: Path, settings: Settings
) -> None:
    link = tmp_path / "minimal.yaml"
    link.symlink_to(secret_file)

    findings = run_check([link], settings)

    assert [(Path(f.file).name, f.rule) for f in findings] == [("minimal.yaml", "symlink")]
    assert_nothing_leaks(findings, secret_file)


def test_linked_folder_is_refused_without_listing_it(
    tmp_path: Path, secret_file: Path, settings: Settings
) -> None:
    link = tmp_path / "catalog"
    link.symlink_to(secret_file.parent, target_is_directory=True)

    findings = run_check([link], settings)

    assert [(Path(f.file).name, f.rule) for f in findings] == [("catalog", "symlink")]
    assert_nothing_leaks(findings, secret_file)


def test_link_to_a_valid_entry_is_refused_too(tmp_path: Path, settings: Settings) -> None:
    folder = tmp_path / "catalog"
    folder.mkdir()
    (folder / "minimal.yaml").symlink_to(MINIMAL)

    findings = run_check([folder], settings)

    assert [(f.rule, f.severity) for f in findings] == [("symlink", Severity.ERROR)]


def test_command_output_never_shows_the_link_target(
    tmp_path: Path, secret_file: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    link = tmp_path / "minimal.yaml"
    link.symlink_to(secret_file)

    code = main(["--today", "2026-11-19", str(link)])

    out = capsys.readouterr()
    assert code == 1
    assert MARKER not in out.out + out.err
    assert "outside" not in out.out + out.err
