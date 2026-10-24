"""The GPU vs Python replication report, on synthetic results."""

from bridge.gpu_report import compare, write_comparison
from experiments.run import _write_csv, result_dir
from replication.targets import TARGETS

II_4_CC = [t for t in TARGETS if t.experiment == "II-4" and t.name == "carrying capacity"]
II_1 = [t for t in TARGETS if t.experiment == "II-1"]


def _results(out_dir, exp_id, population, seeds=2):
    folder = result_dir(exp_id, out_dir)
    folder.mkdir(parents=True)
    for k in range(seeds):
        _write_csv(folder / f"seed{k}.csv", [{"t": t, "population": float(population)} for t in range(501)])


def test_compare_both_sides(tmp_path):
    _results(tmp_path / "gpu", "II-4", 230)
    _results(tmp_path / "py", "II-4", 220)
    (row,) = compare(II_4_CC, tmp_path / "gpu", tmp_path / "py")
    assert row.gpu.status == "pass" and row.py.status == "pass"
    assert row.gpu.observed_mean - row.py.observed_mean == 10


def test_missing_side_is_none(tmp_path):
    rows = compare(II_1, tmp_path / "gpu", tmp_path / "py")
    assert rows[0].gpu is None and rows[0].py is None
    report = tmp_path / "REPORT.md"
    write_comparison(rows, report)
    assert "not run" in report.read_text(encoding="utf-8")


def test_status_change_listed(tmp_path):
    _results(tmp_path / "gpu", "II-4", 300)
    _results(tmp_path / "py", "II-4", 220)
    report = tmp_path / "REPORT.md"
    write_comparison(compare(II_4_CC, tmp_path / "gpu", tmp_path / "py"), report)
    text = report.read_text(encoding="utf-8")
    changes = text.split("## Status changes", 1)[1]
    assert "II-4" in changes and "carrying capacity" in changes and "Python pass → GPU fail" in changes
