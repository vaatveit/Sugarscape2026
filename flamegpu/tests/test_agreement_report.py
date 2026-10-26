"""The agreement report (spec 2026-10-25-gpu-full-parity, section 7; Part A, Task 8): the Julia agreement rule, GPU seeds
against Python's, from result folders."""

import csv
from pathlib import Path

import numpy as np

from bridge.agreement_report import build_report, write_report

EXP = "TEST-tiny"  # 5 steps, so four windows of the periods 0..5


def _write(folder: Path, seeds: list[list[dict]], timing: dict | None = None) -> None:
    run = folder / EXP
    run.mkdir(parents=True)
    for k, series in enumerate(seeds):
        with (run / f"seed{k}.csv").open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(series[0]))
            writer.writeheader()
            writer.writerows({key: repr(v) for key, v in row.items()} for row in series)
    if timing:
        with (run / "timing.csv").open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["seed", "periods", "setup_s", "stepping_s", "metrics_s",
                                                   "agents_start", "agents_end"])
            writer.writeheader()
            for k in range(len(seeds)):
                writer.writerow({"seed": k, "periods": 10, "agents_start": 20, "agents_end": 20, **timing})


def _seeds(rng, n=10, shift=0.0):
    # 5 steps: the quarters are t = 0, 1-2, 3 and 4-5; a shift at t = 0 is in the first only.
    return [[{"t": t, "population": float(20 + t), "gini": 0.3 + 0.01 * rng.standard_normal() + (shift if t == 0 else 0.0)}
             for t in range(6)] for _ in range(n)]


def test_identical_series_no_flags(tmp_path):
    seeds = _seeds(np.random.default_rng(1))
    _write(tmp_path / "py", seeds)
    _write(tmp_path / "gpu", seeds)
    report = build_report([EXP], tmp_path / "gpu", tmp_path / "py")
    assert report.flagged == [] and report.tested > 0


def test_shifted_series_flagged(tmp_path):
    rng = np.random.default_rng(2)
    _write(tmp_path / "py", _seeds(rng))
    _write(tmp_path / "gpu", _seeds(rng, shift=0.05))
    report = build_report([EXP], tmp_path / "gpu", tmp_path / "py")
    assert [(c.metric, c.window) for c in report.flagged] == [("gini", 0)]
    write_report(report, tmp_path / "A.md")
    text = (tmp_path / "A.md").read_text(encoding="utf-8")
    assert "gini" in text and "1 flagged" in text


def test_speed_table_ratio(tmp_path):
    seeds = _seeds(np.random.default_rng(3))
    _write(tmp_path / "py", seeds, {"setup_s": 0.5, "stepping_s": 10.0, "metrics_s": 1.0})
    _write(tmp_path / "gpu", seeds, {"setup_s": 2.0, "stepping_s": 1.0, "metrics_s": 0.5})
    report = build_report([EXP], tmp_path / "gpu", tmp_path / "py")
    (speed,) = report.speed
    assert speed.gpu_step_ms == 100.0 and speed.py_step_ms == 1000.0 and speed.ratio == 0.1


def test_missing_side_not_run(tmp_path):
    _write(tmp_path / "py", _seeds(np.random.default_rng(4)))
    (tmp_path / "gpu").mkdir()
    report = build_report([EXP], tmp_path / "gpu", tmp_path / "py")
    assert report.not_run == [EXP] and report.tested == 0
    write_report(report, tmp_path / "A.md")
    assert "not run" in (tmp_path / "A.md").read_text(encoding="utf-8")
