import random
from pathlib import Path

import pytest

from bridge.report import build_report, write_report
from experiments.run import TIMING_COLUMNS, _write_csv, fingerprint, result_dir

EXP = "II-1"  # 100 periods, 5 seeds


def _series(seed: int, shift: float, steps: int = 100) -> list[dict]:
    rng = random.Random(seed)
    return [{"t": t, "population": 300.0 + shift + rng.gauss(0, 1), "mean_vision": 3.5 + rng.gauss(0, 0.01)}
            for t in range(steps + 1)]


def _folder(root, side: str, shift: float, timed: bool, seeds: int = 5, step_s: float = 1.0):
    folder = result_dir(EXP, root)
    folder.mkdir(parents=True)
    for k in range(seeds):
        _write_csv(folder / f"seed{k}.csv", _series(100 * (side == "julia") + k, shift))
    prefix = "julia\n" if side == "julia" else ""
    (folder / "fingerprint.txt").write_text(prefix + fingerprint(EXP), encoding="utf-8")
    if timed:
        rows = [dict(zip(TIMING_COLUMNS, (k, 100, 0.5, step_s * 100, 0.1, 400, 300))) for k in range(seeds)]
        _write_csv(folder / "timing.csv", rows)
        (folder / "machine.txt").write_text("jobs = 1\nuser_note = test\n", encoding="utf-8")


def test_report_flags_a_planted_shift_and_reads_speed(tmp_path):
    py, jl = tmp_path / "py", tmp_path / "jl"
    _folder(py, "python", 0.0, timed=True, step_s=0.5)
    _folder(jl, "julia", 25.0, timed=True, step_s=0.01)
    report = build_report(jl, py, xl=False, only="II-1")
    flagged = [t for t in report.tests if t.flagged]
    assert {(t.metric, t.window) for t in flagged} == {("population", w) for w in range(4)}
    assert not report.agrees
    speed = report.speed[0]
    assert speed.experiment == EXP and speed.python_step == 0.5 and speed.julia_step == 0.01
    assert speed.speedup == 50.0
    path = tmp_path / "REPORT.md"
    write_report(report, path)
    text = path.read_text(encoding="utf-8")
    assert "population" in text and "50" in text and "does not agree" in text and "Seed-level p" in text


def test_report_names_untimed_and_stale_inputs(tmp_path):
    py, jl = tmp_path / "py", tmp_path / "jl"
    _folder(py, "python", 0.0, timed=False)
    _folder(jl, "julia", 0.0, timed=True)
    (result_dir(EXP, jl) / "fingerprint.txt").write_text("julia\nold settings\n", encoding="utf-8")
    report = build_report(jl, py, xl=False, only="II-1")
    status = report.inputs[EXP]
    assert "untimed" in status["python"] and "stale" in status["julia"]
    assert report.speed[0].python_step is None
    assert not [t for t in report.tests if t.flagged]


def test_a_column_the_results_do_not_record_leaves_the_target_unscored(tmp_path):
    py, jl = tmp_path / "py", tmp_path / "jl"
    _folder(py, "python", 0.0, timed=True)  # II-1's target reads "moved", which _series does not write
    _folder(jl, "julia", 0.0, timed=True)
    (row,) = build_report(jl, py, xl=False, only="II-1").targets
    assert row.python is None and row.julia is None


def test_other_key_errors_in_scoring_are_not_hidden(tmp_path, monkeypatch):
    import bridge.report

    def broken(*args):
        raise KeyError("population")  # a column the results do record: a bug, not a gap

    monkeypatch.setattr(bridge.report, "evaluate", broken)
    py, jl = tmp_path / "py", tmp_path / "jl"
    _folder(py, "python", 0.0, timed=True)
    _folder(jl, "julia", 0.0, timed=True)
    with pytest.raises(KeyError):
        build_report(jl, py, xl=False, only="II-1")


def test_verdict_line_counts_experiments_compared_from_stale_or_incomplete_results(tmp_path):
    py, jl = tmp_path / "py", tmp_path / "jl"
    _folder(py, "python", 0.0, timed=True, seeds=4)  # II-1 runs 5 seeds
    _folder(jl, "julia", 0.0, timed=True)
    report = build_report(jl, py, xl=False, only="II-1")
    assert report.caveats == [EXP]
    path = tmp_path / "REPORT.md"
    write_report(report, path)
    verdict = next(line for line in path.read_text(encoding="utf-8").splitlines() if line.startswith("**Julia"))
    assert "Compared from stale or incomplete results: 1 of the 1 experiments" in verdict


def test_python_results_default_to_the_checkout_holding_julia(tmp_path, monkeypatch):
    import importlib.util
    import shutil
    import sys

    import bridge.paths

    copy = tmp_path / "checkout" / "julia" / "bridge" / "paths.py"  # a checkout somewhere else
    copy.parent.mkdir(parents=True)
    shutil.copy(bridge.paths.__file__, copy)
    monkeypatch.delenv("SUGARSCAPE_RESULTS_ROOT", raising=False)
    monkeypatch.setattr(sys, "path", list(sys.path))  # loading it puts that checkout on sys.path
    spec = importlib.util.spec_from_file_location("paths_copy", copy)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.PY_RESULTS == tmp_path / "checkout"
