"""Julia's results read back through the Python runner's own reader, column for column."""

import math
import shutil
import subprocess

import pytest

from bridge.paths import REPO_ROOT
from experiments.run import TIMING_COLUMNS, _parse, _read_csv, timed_seed

JULIA = shutil.which("julia")
pytestmark = pytest.mark.skipif(JULIA is None, reason="julia is not on PATH")


def _julia(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([JULIA, "--project=julia", *args], cwd=REPO_ROOT, capture_output=True, text=True,
                          timeout=900)


def test_julia_csv_reads_like_python(tmp_path):
    done = _julia("julia/run.jl", "TEST-tiny", "--out", str(tmp_path))
    assert done.returncode == 0, done.stderr
    rows = _read_csv(tmp_path / "TEST-tiny" / "seed0.csv")
    assert list(rows[0]) == list(timed_seed("TEST-tiny", 0)[0][0])
    assert [r["t"] for r in rows] == [0, 1, 2, 3, 4, 5] and all(type(r["t"]) is int for r in rows)
    assert rows[0]["population"] == 20.0 and type(rows[0]["population"]) is float
    timing = _read_csv(tmp_path / "TEST-tiny" / "timing.csv")
    assert tuple(timing[0]) == TIMING_COLUMNS and len(timing) == 2


def test_special_values_round_trip():  # Review Focus 4
    code = ("using Sugarscape; print(join(Sugarscape.format_value.("
            "Any[NaN, Inf, -Inf, -0.0, 1e300, 1e-300, 0.1 + 0.2, 7]), \",\"))")
    done = _julia("-e", code)
    assert done.returncode == 0, done.stderr
    values = [_parse(v) for v in done.stdout.split(",")]
    assert math.isnan(values[0]) and values[1:3] == [math.inf, -math.inf]
    assert values[3] == 0.0 and math.copysign(1.0, values[3]) == -1.0
    assert values[4:7] == [1e300, 1e-300, 0.1 + 0.2]
    assert values[7] == 7 and type(values[7]) is int
