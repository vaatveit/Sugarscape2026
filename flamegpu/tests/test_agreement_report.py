"""The agreement report (spec 2026-10-25-gpu-full-parity, section 7; Part A, Task 8): the Julia agreement rule, GPU seeds
against Python's, from result folders."""

import csv
from pathlib import Path

import numpy as np

from bridge.agreement_report import build_report, write_report

EXP = "TEST-tiny"  # 5 steps, so four windows of the periods 0..5


def _write(folder: Path, seeds: list[list[dict]], timing: dict | None = None, fingerprint: str | None = None) -> None:
    run = folder / EXP
    run.mkdir(parents=True)
    if fingerprint is not None:
        (run / "fingerprint.txt").write_text(fingerprint, encoding="utf-8")
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


def test_zero_periods_speed_is_nan(tmp_path):
    # A run of 0 periods has no stepping time per period: NaN in the speed table, not a crash.
    seeds = _seeds(np.random.default_rng(5))
    _write(tmp_path / "py", seeds, {"setup_s": 0.5, "stepping_s": 0.0, "metrics_s": 0.0, "periods": 0})
    _write(tmp_path / "gpu", seeds, {"setup_s": 2.0, "stepping_s": 0.0, "metrics_s": 0.0, "periods": 0})
    report = build_report([EXP], tmp_path / "gpu", tmp_path / "py")
    (speed,) = report.speed
    assert speed.gpu_setup_s == 2.0 and np.isnan(speed.gpu_step_ms) and np.isnan(speed.py_metrics_ms)
    write_report(report, tmp_path / "A.md")
    assert "| TEST-tiny | 2 | nan |" in (tmp_path / "A.md").read_text(encoding="utf-8")


# --- Part F (plan 2026-10-27-gpu-parity-part-f, Task 2): xl, a Julia reference, Julia's timings --------------------

TIMING = {"setup_s": 0.5, "stepping_s": 10.0, "metrics_s": 1.0}


def _gpu_fp(xl: bool = False) -> str:
    from bridge.gpu_run import gpu_fingerprint

    return gpu_fingerprint(EXP, xl)


def _py_fp(xl: bool = False) -> str:
    from experiments.run import fingerprint

    return fingerprint(EXP, xl)


def test_xl_julia_reference(tmp_path):
    seeds = _seeds(np.random.default_rng(6))
    _write(tmp_path / "jl", seeds, fingerprint="julia\n" + _py_fp())
    _write(tmp_path / "gpu", seeds, fingerprint=_gpu_fp())
    report = build_report([EXP], tmp_path / "gpu", tmp_path / "jl", reference="julia")
    assert report.flagged == [] and report.tested > 0 and report.stale == []
    write_report(report, tmp_path / "A.md")
    assert "Julia" in (tmp_path / "A.md").read_text(encoding="utf-8").splitlines()[0]


def test_julia_stale_listed(tmp_path):
    seeds = _seeds(np.random.default_rng(7))
    _write(tmp_path / "jl", seeds, fingerprint="julia\nold\n")
    _write(tmp_path / "gpu", seeds, fingerprint=_gpu_fp())
    assert build_report([EXP], tmp_path / "gpu", tmp_path / "jl", reference="julia").stale == [EXP]


def test_speed_table_julia_column(tmp_path):
    seeds = _seeds(np.random.default_rng(8))
    _write(tmp_path / "py", seeds, TIMING)
    _write(tmp_path / "gpu", seeds, {**TIMING, "stepping_s": 1.0})
    _write(tmp_path / "jl", seeds, {**TIMING, "stepping_s": 2.0})
    (speed,) = build_report([EXP], tmp_path / "gpu", tmp_path / "py", julia_dir=tmp_path / "jl").speed
    assert speed.julia_step_ms == 200.0 and speed.julia_ratio == 0.5
    report = build_report([EXP], tmp_path / "gpu", tmp_path / "py", julia_dir=tmp_path / "missing")
    (speed,) = report.speed
    assert np.isnan(speed.julia_step_ms) and np.isnan(speed.julia_ratio)
    write_report(report, tmp_path / "A.md")
    row = next(line for line in (tmp_path / "A.md").read_text(encoding="utf-8").splitlines()
               if line.startswith(f"| {EXP} |"))
    assert row.endswith("| nan | nan |")


def test_timing_dir_overrides(tmp_path):
    seeds = _seeds(np.random.default_rng(9))
    _write(tmp_path / "py", seeds, TIMING)
    _write(tmp_path / "gpu", seeds, TIMING)
    _write(tmp_path / "fast", seeds, {**TIMING, "stepping_s": 0.5})
    (speed,) = build_report([EXP], tmp_path / "gpu", tmp_path / "py", timing_dir=tmp_path / "fast").speed
    assert speed.gpu_step_ms == 50.0


def test_xl_fingerprints(tmp_path):
    # With --xl both sides are checked against the xl fingerprints: regular ones read stale.
    seeds = _seeds(np.random.default_rng(10))
    _write(tmp_path / "py", seeds, fingerprint=_py_fp())
    _write(tmp_path / "gpu", seeds, fingerprint=_gpu_fp(xl=True))
    assert build_report([EXP], tmp_path / "gpu", tmp_path / "py", xl=True).stale == [EXP]
    (tmp_path / "py" / EXP / "fingerprint.txt").write_text(_py_fp(xl=True), encoding="utf-8")
    (tmp_path / "gpu" / EXP / "fingerprint.txt").write_text(_gpu_fp(), encoding="utf-8")
    assert build_report([EXP], tmp_path / "gpu", tmp_path / "py", xl=True).stale == [EXP]
    (tmp_path / "gpu" / EXP / "fingerprint.txt").write_text(_gpu_fp(xl=True), encoding="utf-8")
    assert build_report([EXP], tmp_path / "gpu", tmp_path / "py", xl=True).stale == []


def test_incomplete_side_listed_stale(tmp_path):
    # A folder with a current fingerprint but fewer seeds than registered (TEST-tiny: 2) is listed, GPU or Julia,
    # as Python's results_current lists it: never scored as if complete.
    _write(tmp_path / "jl", _seeds(np.random.default_rng(11), n=2), fingerprint="julia\n" + _py_fp())
    _write(tmp_path / "gpu", _seeds(np.random.default_rng(12), n=1), fingerprint=_gpu_fp())
    assert build_report([EXP], tmp_path / "gpu", tmp_path / "jl", reference="julia").stale == [EXP]
    _write(tmp_path / "jl1", _seeds(np.random.default_rng(13), n=1), fingerprint="julia\n" + _py_fp())
    _write(tmp_path / "gpu2", _seeds(np.random.default_rng(14), n=2), fingerprint=_gpu_fp())
    assert build_report([EXP], tmp_path / "gpu2", tmp_path / "jl1", reference="julia").stale == [EXP]
    assert build_report([EXP], tmp_path / "gpu2", tmp_path / "jl", reference="julia").stale == []
