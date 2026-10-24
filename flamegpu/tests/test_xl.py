"""xl (docs/xl.md) at 500x500: the configuration loads, and short runs keep every invariant."""

from dataclasses import replace

import pytest

from bridge.config_cfg import config_to_cfg
from conftest import run_exe
from experiments.run import experiment_config
from gpu import parse_printed, read_rows

# II-8's pollution starts at t = 50 and diffusion at t = 100; moved to 0 so five periods exercise the 100 passes.
XL_CASES = {
    "II-4-gini": (lambda cfg: cfg, 25_000),
    "II-8": (lambda cfg: replace(cfg, pollution_start=0, diffusion_start=0), 40_000),
}


def _write(tmp_path, cfg):
    path = tmp_path / "run.cfg"
    path.write_text(config_to_cfg(cfg, steps=5, seed=0), encoding="utf-8")
    return path


def test_xl_print_config(exe, tmp_path):
    result = run_exe(exe, "--config", _write(tmp_path, experiment_config("II-4", xl=True)), "--print-config")
    assert result.returncode == 0, result.stderr
    printed = parse_printed(result.stdout)
    assert printed["map_cells"] == "250000" and printed["width"] == "500"


@pytest.mark.parametrize("exp_id", XL_CASES)
def test_xl_runs_clean(exe, tmp_path, exp_id):
    adjust, founders = XL_CASES[exp_id]
    cfg = _write(tmp_path, adjust(experiment_config(exp_id, xl=True)))
    agents = tmp_path / "agents.csv"
    result = run_exe(exe, "--config", cfg, "--check", "--dump-agents", agents, "--dump-at", "0")
    assert result.returncode == 0, result.stderr
    rows = read_rows(agents)
    assert len(rows) == founders
    visions = {a["vision"] for a in rows}
    assert min(visions) == 10 and max(visions) == 60  # every whole number in [10, 60] (docs/xl.md)
