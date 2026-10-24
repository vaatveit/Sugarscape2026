"""The bridge: registered Configs to run.cfg, and running registered experiments on the GPU."""

import pytest

from bridge.config_cfg import UnsupportedFeature, config_to_cfg, unsupported_features
from bridge.gpu_run import matching_ids, run_experiment_gpu
from conftest import run_exe
from experiments.registry import EXPERIMENTS
from experiments.run import load_results
from sugarscape.config import Config


def _lines(text: str) -> set[str]:
    return {line.strip() for line in text.splitlines()}


def test_cfg_ii1_has_inf_growback():
    lines = _lines(config_to_cfg(EXPERIMENTS["II-1"].config, steps=100, seed=0))
    assert "growback_rate = inf" in lines
    assert "endowment = 25,50" in lines


def test_cfg_ii8_pollution():
    lines = _lines(config_to_cfg(EXPERIMENTS["II-8"].config, steps=200, seed=0))
    assert {"pollution = 1.0,1.0", "pollution_start = 50", "diffusion_period = 1", "diffusion_start = 100"} <= lines


def test_cfg_none_fields_blank():
    lines = _lines(config_to_cfg(EXPERIMENTS["II-4"].config, steps=500, seed=0))
    assert "max_age =" in lines
    assert "seasons =" in lines


def test_cfg_steps_and_seed():
    lines = _lines(config_to_cfg(EXPERIMENTS["II-4"].config, steps=500, seed=13))
    assert {"steps = 500", "seed = 13"} <= lines


def test_unsupported_lists_features():
    cfg = Config(sex=True, max_age=(60, 100))
    assert unsupported_features(cfg) == ["sex"]
    with pytest.raises(UnsupportedFeature, match="sex"):
        config_to_cfg(cfg, steps=10, seed=0)


def test_chapter_ii_configs_are_supported():
    ids = [i for i in EXPERIMENTS if i.startswith("II-")]
    assert len(ids) == 25
    assert all(unsupported_features(EXPERIMENTS[i].config) == [] for i in ids)


def test_matching_chapter_prefix():
    ids = matching_ids("II", EXPERIMENTS)
    assert len(ids) == 25 and all(i.startswith("II-") for i in ids)
    assert matching_ids("II-5", EXPERIMENTS) == [i for i in EXPERIMENTS if i.startswith("II-5/")]
    assert matching_ids("II-4", EXPERIMENTS) == ["II-4"]


def test_every_chapter_ii_experiment_converts(exe, tmp_path):
    for exp_id in (i for i in EXPERIMENTS if i.startswith("II-")):
        exp = EXPERIMENTS[exp_id]
        cfg = tmp_path / f"{exp_id.replace('/', '_')}.cfg"
        cfg.write_text(config_to_cfg(exp.config, steps=exp.steps, seed=exp.config.seed), encoding="utf-8")
        result = run_exe(exe, "--config", cfg, "--print-config")
        assert result.returncode == 0, (exp_id, result.stderr)


def test_run_tiny_experiment(exe, tmp_path):
    paths = run_experiment_gpu("TEST-tiny", out_dir=tmp_path, exe=exe)
    assert len(paths) == 2
    series = load_results("TEST-tiny", tmp_path)
    assert len(series) == 2 and all(len(s) == 6 for s in series)
    assert (tmp_path / "TEST-tiny" / "fingerprint.txt").read_text(encoding="utf-8").startswith("gpu-phase1")
