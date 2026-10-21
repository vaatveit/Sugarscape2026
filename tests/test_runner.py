from experiments.registry import EXPERIMENTS
from experiments.run import load_results, matching_ids, results_current, run_experiment
from replication.report import load_or_run


def test_same_seed_same_csv(tmp_path):
    run_experiment("TEST-tiny", out_dir=tmp_path / "a")
    run_experiment("TEST-tiny", out_dir=tmp_path / "b", jobs=2)
    for k in range(2):
        a = (tmp_path / "a" / "TEST-tiny" / f"seed{k}.csv").read_bytes()
        assert a == (tmp_path / "b" / "TEST-tiny" / f"seed{k}.csv").read_bytes()


def test_seeds_differ(tmp_path):
    run_experiment("TEST-tiny", out_dir=tmp_path)
    s0 = (tmp_path / "TEST-tiny" / "seed0.csv").read_bytes()
    assert s0 != (tmp_path / "TEST-tiny" / "seed1.csv").read_bytes()


def test_series_has_every_period(tmp_path):
    series = run_experiment("TEST-tiny", seeds=1, out_dir=tmp_path)[0]
    assert [row["t"] for row in series] == [0, 1, 2, 3, 4, 5]


def test_load_results_round_trips(tmp_path):
    out = run_experiment("TEST-tiny", out_dir=tmp_path)
    assert load_results("TEST-tiny", out_dir=tmp_path) == out


def test_writes_summary_plot(tmp_path):
    run_experiment("TEST-tiny", seeds=1, out_dir=tmp_path)
    assert (tmp_path / "TEST-tiny" / "summary.png").stat().st_size > 0


def test_id_matching_is_exact_or_slash_prefix():
    ids = ["II-4", "II-4-gini", "II-5/m1/v1", "II-5/m2/v1"]
    assert matching_ids("II-4", ids) == ["II-4"]
    assert matching_ids("II-5", ids) == ["II-5/m1/v1", "II-5/m2/v1"]


def test_tiny_experiment_registered():
    assert EXPERIMENTS["TEST-tiny"].steps == 5 and EXPERIMENTS["TEST-tiny"].seeds == 2


def test_results_fingerprint_detects_changed_settings(tmp_path):
    assert not results_current("TEST-tiny", tmp_path)              # nothing saved yet
    run_experiment("TEST-tiny", out_dir=tmp_path)
    assert results_current("TEST-tiny", tmp_path)
    (tmp_path / "TEST-tiny" / "fingerprint.txt").write_text("stale settings")
    assert not results_current("TEST-tiny", tmp_path)
    load_or_run("TEST-tiny", out_dir=tmp_path)                    # reruns instead of reusing
    assert results_current("TEST-tiny", tmp_path)
