"""The semantics harness (spec 2026-10-25-gpu-full-parity, "What was measured"; Part A, Task 8): Python's model with the
GPU's turn semantics."""

from bridge.semantics_harness import HybridModel, main, run_seed
from experiments.registry import EXPERIMENTS
from experiments.run import experiment_config, sugarscape_metrics, load_results


def test_harness_runs(tmp_path):
    run_seed(tmp_path, "III-1", 0, steps=3)
    (series,) = load_results("III-1", tmp_path)
    assert [r["t"] for r in series] == [0, 1, 2, 3]
    assert list(series[0]) == ["t", *sugarscape_metrics(HybridModel(experiment_config("III-1")))]


def test_harness_seeds_option(tmp_path):
    # --seeds runs more seeds than registered (TEST-tiny: 2), as Part F's 60-seed study of III-7 and VI-3 did.
    main(["TEST-tiny", "--seeds", "3", "--out", str(tmp_path)])
    assert len(load_results("TEST-tiny", tmp_path)) == 3


def test_harness_refuses_combat():
    import pytest

    model = HybridModel(experiment_config("III-9"))
    with pytest.raises(ValueError, match="combat"):
        model.step()
    assert EXPERIMENTS["III-9"].config.combat_alpha is not None
