"""Replacement, the --check invariants, and determinism on the full 50x50 sugarscape."""

import pytest

from gpu import run_gpu

II_4 = {}
II_8 = {"pollution": "1.0,1.0", "pollution_start": "50", "diffusion_period": "1", "diffusion_start": "100"}
II_4_GINI = {"initial_population": "250", "max_age": "60,100", "replacement": "true", "endowment": "5,25"}


def test_replacement_keeps_population(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, II_4_GINI, steps=120, extra_args=("--check",))
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == 250


def test_replacement_keeps_occupancy_consistent(exe, tmp_path):
    # Newcomers mark their own sites; --check fails if any agent's site is unmarked or two agents share one.
    dump = run_gpu(exe, tmp_path, II_4_GINI, steps=60, extra_args=("--check",))
    assert dump.returncode == 0, dump.stderr


@pytest.mark.parametrize("seed", range(5))
@pytest.mark.parametrize("name,cfg", [("II-4", II_4), ("II-8", II_8), ("II-4-gini", II_4_GINI)])
def test_invariants_hold(exe, tmp_path, name, cfg, seed):
    dump = run_gpu(exe, tmp_path, {**cfg, "seed": str(seed)}, steps=150, extra_args=("--check",))
    assert dump.returncode == 0, dump.stderr


def _dump_files(exe, directory, seed):
    directory.mkdir()
    dump = run_gpu(exe, directory, {"seed": str(seed)}, steps=60)
    assert dump.returncode == 0, dump.stderr
    return (directory / "agents.csv").read_bytes(), (directory / "landscape.csv").read_bytes()


def test_same_seed_same_result(exe, tmp_path):
    first = _dump_files(exe, tmp_path / "a", 7)
    assert _dump_files(exe, tmp_path / "b", 7) == first
    assert _dump_files(exe, tmp_path / "c", 8) != first
