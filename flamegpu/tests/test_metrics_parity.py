"""The 45 metric columns against Python's sugarscape_metrics (spec 2026-10-25-gpu-full-parity, Task 3).

Scenarios where the order and the draws cannot matter, as in test_parity: distinct capacities, agents far apart.
"""

import math

from gpu import read_rows, run_gpu
from reference import python_metric_rows
from test_parity import CAPACITY

TAGGED = [
    # Both tribes on both sides of the 20x20 anti-diagonal (x + y < 20 is the SW side).
    {"x": 2, "y": 2, "vision": 1, "metabolism": 1, "sugar": 10.0, "age": 20, "max_age": 90, "tags": "00011",
     "sex": "F", "fertility_start": 12, "fertility_end": 45, "initial_sugar": 9.0, "n_children": 2},
    {"x": 12, "y": 2, "vision": 2, "metabolism": 2, "sugar": 11.0, "age": 30, "max_age": 80, "tags": "11100",
     "sex": "M", "fertility_start": 13, "fertility_end": 55, "initial_sugar": 11.0},
    {"x": 2, "y": 12, "vision": 3, "metabolism": 3, "sugar": 12.0, "age": 40, "max_age": 70, "tags": "10101",
     "sex": "F", "fertility_start": 14, "fertility_end": 41, "initial_sugar": 12.0, "n_children": 1},
    {"x": 12, "y": 12, "vision": 3, "metabolism": 4, "sugar": 13.0, "age": 50, "max_age": 60, "tags": "00000",
     "sex": "M", "fertility_start": 15, "fertility_end": 52, "initial_sugar": 7.5},
]
CFG = {"tag_length": "5", "sex": "true", "max_age": "60,100"}


def _gpu_rows(exe, tmp_path, cfg, agents, steps):
    out = tmp_path / "metrics.csv"
    dump = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps, extra_args=("--out", out))
    assert dump.returncode == 0, dump.stderr
    return read_rows(out)


def _same(a, b) -> bool:
    if isinstance(a, float) and math.isnan(a):
        return isinstance(b, float) and math.isnan(b)
    return math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12)


def _compare(gpu: dict, py: dict) -> list[str]:
    return [f"{k}: gpu {gpu.get(k)} python {v}" for k, v in py.items() if k not in gpu or not _same(gpu[k], v)]


def test_t0_row_matches_python(exe, tmp_path):
    gpu = _gpu_rows(exe, tmp_path, CFG, TAGGED, steps=1)
    py = python_metric_rows(CFG, CAPACITY, TAGGED, steps=0)
    assert _compare(gpu[0], py[0]) == []


def test_one_step_matches_python(exe, tmp_path):
    cfg = {"tag_length": "5"}
    agents = [{k: v for k, v in a.items() if k in ("x", "y", "vision", "metabolism", "sugar", "tags")} for a in TAGGED]
    gpu = _gpu_rows(exe, tmp_path, cfg, agents, steps=2)
    py = python_metric_rows(cfg, CAPACITY, agents, steps=2)
    for g, p in zip(gpu, py):
        assert _compare(g, p) == [], g["t"]


def test_csv_header_is_pythons(exe, tmp_path):
    out = tmp_path / "metrics.csv"
    dump = run_gpu(exe, tmp_path, {}, CAPACITY, TAGGED[:1], 1, extra_args=("--out", out))
    assert dump.returncode == 0, dump.stderr
    header = out.read_text().splitlines()[0].split(",")
    assert header == list(python_metric_rows({}, CAPACITY, TAGGED[:1], 0)[0])  # "t", then sugarscape_metrics' keys
    assert len(header) == 46
