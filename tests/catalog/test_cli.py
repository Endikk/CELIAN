"""Command line: options, output format and exit code."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta, timezone

import pytest
from catalog_testing import INVALID_DIR, VALID_DIR
from check_catalog import main, utc_today


def test_valid_folder_exits_zero_and_prints_a_summary(
    capsys: pytest.CaptureFixture[str],
) -> None:
    code = main(["--today", "2026-11-19", str(VALID_DIR)])

    out = capsys.readouterr().out
    assert code == 0
    assert out.splitlines()[-1] == "1 catalog file checked: 0 errors, 1 warning"


def test_error_exits_one_and_names_file_path_and_rule(
    capsys: pytest.CaptureFixture[str],
) -> None:
    example = INVALID_DIR / "oss-without-license.yaml"

    code = main(["--today", "2026-11-19", str(example)])

    first = capsys.readouterr().out.splitlines()[0]
    assert code == 1
    assert first.startswith("error: ")
    assert first.endswith(
        "oss-without-license.yaml: targets/local: [schema:required] "
        "'license' is a required property"
    )


@pytest.mark.parametrize("value", ["2026-11-31", "20261119", "2026-1-9", "2026-11-19\n", "today"])
def test_today_option_accepts_only_a_real_iso_date(value: str) -> None:
    with pytest.raises(SystemExit) as raised:
        main(["--today", value, str(VALID_DIR)])

    assert raised.value.code == 2


def test_default_today_is_the_utc_date() -> None:
    # 23:30 in New York on 2026-11-19 is already 2026-11-20 in UTC.
    new_york = timezone(timedelta(hours=-5))
    late_evening = datetime(2026, 11, 19, 23, 30, tzinfo=new_york)

    assert utc_today(lambda: late_evening).isoformat() == "2026-11-20"
    assert utc_today(lambda: late_evening.astimezone(UTC)).isoformat() == "2026-11-20"
