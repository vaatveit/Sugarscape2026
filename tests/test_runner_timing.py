import csv

from experiments.run import TIMING_COLUMNS, run_experiment


def rows(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def test_timing_has_one_row_per_seed(tmp_path):
    runs = run_experiment("TEST-tiny", out_dir=tmp_path)
    timing = rows(tmp_path / "TEST-tiny" / "timing.csv")
    assert [r["seed"] for r in timing] == ["0", "1"] and tuple(timing[0]) == TIMING_COLUMNS
    for r, series in zip(timing, runs):
        assert all(float(r[k]) >= 0 for k in ("setup_s", "stepping_s", "metrics_s"))
        assert int(r["periods"]) == 5 and int(r["agents_start"]) == 20
        assert int(r["agents_end"]) == series[-1]["population"]


def test_machine_note(tmp_path):
    run_experiment("TEST-tiny", out_dir=tmp_path)
    note = (tmp_path / "TEST-tiny" / "machine.txt").read_text()
    assert all(f"{k} = " in note for k in ("python", "numpy", "platform", "processor", "jobs"))
    assert "share the processor" not in note


def test_parallel_timing_comes_back_per_seed(tmp_path):
    run_experiment("TEST-tiny", out_dir=tmp_path, jobs=2)
    assert len(rows(tmp_path / "TEST-tiny" / "timing.csv")) == 2
    assert "share the processor" in (tmp_path / "TEST-tiny" / "machine.txt").read_text()


def test_variant_kinds_are_timed_too(tmp_path):
    run_experiment("TEST-ring", out_dir=tmp_path)
    assert len(rows(tmp_path / "TEST-ring" / "timing.csv")) == 2
