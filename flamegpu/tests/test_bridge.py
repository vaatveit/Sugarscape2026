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


def test_any_other_field_off_default_is_refused():
    from dataclasses import replace

    base = EXPERIMENTS["II-4"].config
    # Fields the GPU program doesn't read, including ones left out of repr, are refused unless at their default.
    assert unsupported_features(replace(base, trade_rounding="down")) == ["trade_rounding"]
    assert unsupported_features(replace(base, mate_contact="neighbors")) == ["mate_contact"]
    with pytest.raises(UnsupportedFeature, match="fertility_threshold"):
        config_to_cfg(replace(base, fertility_threshold=0.5), steps=10, seed=0)


def test_seed_and_chapter_ii_fields_are_free():
    from dataclasses import replace

    base = EXPERIMENTS["II-4"].config
    assert unsupported_features(replace(base, seed=7, width=60, height=60, pollution=(1.0, 2.0))) == []


# --- xl: gpu_run --xl, timing.csv and machine.txt ----------------------------------------------


def test_xl_config_reaches_run_cfg():
    from experiments.run import experiment_config

    text = config_to_cfg(experiment_config("II-8", xl=True), steps=5, seed=0)
    assert "width = 500\n" in text and "vision = 10,60\n" in text
    assert "diffusion_passes = 100\n" in text
    assert [line for line in text.splitlines() if line.startswith("map = ")][0].endswith("sugar-map-xl.txt")


def test_regular_cfg_has_one_pass():
    assert "diffusion_passes = 1\n" in config_to_cfg(EXPERIMENTS["II-4"].config, steps=5, seed=0)


def test_xl_chapter_ii_is_supported():
    from experiments.run import experiment_config

    for exp_id in ("II-4", "II-4-gini", "II-6", "II-7", "II-8", "II-5/m3/v10.5"):
        assert unsupported_features(experiment_config(exp_id, xl=True)) == [], exp_id


def test_mismatched_map_is_refused(exe, tmp_path):
    # Review Focus 1: the 500x500 map in a 50x50 world is an error naming the map, never a misread run.
    from dataclasses import replace

    cfg = tmp_path / "run.cfg"
    cfg.write_text(config_to_cfg(replace(EXPERIMENTS["II-4"].config, sugar_map="sugar-map-xl.txt"), 1, 0),
                   encoding="utf-8")
    result = run_exe(exe, "--config", cfg, "--print-config")
    assert result.returncode == 2
    assert "sugar-map-xl.txt" in result.stderr.splitlines()[0]


def test_gpu_run_xl(exe, tmp_path):
    import csv

    from bridge.gpu_run import GPU_FINGERPRINT
    from experiments.run import TIMING_COLUMNS, fingerprint

    run_experiment_gpu("II-8", seeds=1, out_dir=tmp_path, exe=exe, xl=True)
    folder = tmp_path / "II-8"
    assert len(load_results("II-8", tmp_path)[0]) == 201
    assert (folder / "fingerprint.txt").read_text(encoding="utf-8") == GPU_FINGERPRINT + fingerprint("II-8", xl=True)
    with (folder / "timing.csv").open(newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    assert tuple(reader.fieldnames) == TIMING_COLUMNS
    assert len(rows) == 1 and int(rows[0]["agents_start"]) == 40000
    machine = (folder / "machine.txt").read_text(encoding="utf-8")
    assert "seatbelts = on" in machine and "jobs = 1" in machine


def test_machine_note_with_jobs(exe):
    # Review Focus 5: timings taken side by side say they shared the GPU.
    from bridge.timing import machine_note

    assert "timings taken with --jobs 2 share the GPU" in machine_note(exe, 2)
    assert "share the GPU" not in machine_note(exe, 1)


def test_xl_refuses_other_worlds(capsys):
    from bridge.gpu_run import main

    other = next(i for i, e in EXPERIMENTS.items() if not isinstance(e.config, Config))
    with pytest.raises(SystemExit) as e:
        main([other, "--xl"])
    assert e.value.code == 2
    assert "xl applies to sugarscape experiments" in capsys.readouterr().err  # Python's refusal, not argparse's


def test_default_out_gpu():
    from pathlib import Path

    from bridge.gpu_run import default_out_gpu

    assert default_out_gpu(True) == Path("results-gpu-xl")
    assert default_out_gpu(False) == Path("results-gpu")
