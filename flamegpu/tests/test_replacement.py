"""Replacement R (p.32) on the device: where newcomers land, what they draw, and crowded or tiled worlds."""

import numpy as np
import pytest

from conftest import run_exe
from gpu import read_rows, run_gpu, write_cfg

# Everyone dies every period (max_age 1, founders aged 0), so each end-of-period dump holds only newcomers.
EVERYONE_DIES = {"initial_population": "250", "max_age": "1,1", "replacement": "true", "founder_ages": "zero"}


def test_newcomers_land_uniformly(exe, tmp_path):
    # Each dump holds 250 newcomers placed on a 50x50 world that was empty when they were placed.
    counts = np.zeros(25)
    for seed in range(8):
        for t in (3, 7, 11):
            d = tmp_path / f"{seed}_{t}"
            d.mkdir()
            dump = run_gpu(exe, d, {**EVERYONE_DIES, "seed": str(seed)}, steps=t)
            assert dump.returncode == 0, dump.stderr
            sites = {(a["x"], a["y"]) for a in dump.agents}
            assert len(sites) == 250 and all(a["age"] == 0 for a in dump.agents)
            for x, y in sites:
                counts[(x // 10) + 5 * (y // 10)] += 1
    expected = counts.sum() / 25
    chi2 = ((counts - expected) ** 2 / expected).sum()
    assert chi2 < 60  # 24 degrees of freedom: p ~ 1e-4 at 60; a half-world bias gives chi2 in the thousands


def _float_draw_counts(cells: int) -> np.ndarray:
    """How many of FLAME GPU's 2^24 float draws land on each site with uniform<unsigned int>(0, cells - 1): it
    computes (unsigned)(float(cells) * u), u = (curand() & 0xFFFFFF) / 2^24 (AgentRandom.cuh, uniform(min, max))."""
    u = np.arange(2 ** 24, dtype=np.float32) * np.float32(2.0 ** -24)
    return np.bincount((np.float32(cells) * u).astype(np.int64), minlength=cells)


def test_newcomer_sites_drawn_exactly_in_a_large_world(exe, tmp_path):
    # 2500x2500 (--tile 50): a site draw through a 24-bit float reaches each site 2 or 3 times in 2^24, so newcomers
    # would favour the 3-draw sites. An exact draw lands on sites with mean weight 2^24 / cells (2.684); the float
    # draw gives E[w^2] / E[w] (2.764). 10,000 newcomers on an empty world: standard error about 0.005.
    cells = 2500 * 2500
    weight = _float_draw_counts(cells)
    cfg = write_cfg(tmp_path, **{**EVERYONE_DIES, "initial_population": "4", "steps": "3"})
    result = run_exe(exe, "--config", cfg, "--tile", "50", "--dump-agents", tmp_path / "agents.csv", "--dump-at", "3")
    assert result.returncode == 0, result.stderr
    agents = read_rows(tmp_path / "agents.csv")
    assert len(agents) == 10_000
    landed = np.array([weight[a["x"] + a["y"] * 2500] for a in agents], dtype=float)
    uniform_mean = 2 ** 24 / cells
    assert abs(landed.mean() - uniform_mean) < 4 * landed.std() / np.sqrt(len(landed)), landed.mean()


@pytest.mark.parametrize("population", [2490, 2500])
def test_crowded_world_places_everyone(exe, tmp_path, population):
    # Few empty sites: newcomers must still find them (spec section 2, the scan after PLACE_TRIES misses).
    cfg = {"initial_population": str(population), "max_age": "5,10", "replacement": "true", "endowment": "25,50"}
    dump = run_gpu(exe, tmp_path, cfg, steps=40, extra_args=("--check",))
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == population


def test_newcomer_attributes(exe, tmp_path):
    # Agents of age 0 at the dump were born that period and still hold their exact draws.
    cfg = {"initial_population": "400", "max_age": "3,8", "replacement": "true", "founder_ages": "zero",
           "look_stride": "5", "vision": "5,20", "endowment": "5,25", "metabolism": "1,4"}
    dump = run_gpu(exe, tmp_path, cfg, steps=12)
    assert dump.returncode == 0, dump.stderr
    born = [a for a in dump.agents if a["age"] == 0]
    assert len(born) > 20
    for a in born:
        assert a["vision"] % 5 == 0 and 5 <= a["vision"] <= 20
        assert 1 <= a["metabolism"] <= 4 and 5 <= a["sugar"] <= 25 and a["sugar"] == int(a["sugar"])
        assert 3 <= a["max_age"] <= 8 and 0 <= a["x"] < 50 and 0 <= a["y"] < 50


def test_newcomers_use_tiled_world(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, EVERYONE_DIES, steps=5, extra_args=("--tile", "2"))  # 100x100, 1000 agents
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == 1000
    outside = sum(1 for a in dump.agents if a["x"] >= 50 or a["y"] >= 50)
    assert 0.65 < outside / len(dump.agents) < 0.85  # three tiles in four


def test_metrics_every_with_replacement_and_dump(exe, tmp_path):
    out = tmp_path / "m.csv"
    dump = run_gpu(exe, tmp_path, {**EVERYONE_DIES, "max_age": "2,4"}, steps=9, dump_at=6,
                   extra_args=("--out", out, "--metrics-every", "3"))
    assert dump.returncode == 0, dump.stderr
    assert [r["t"] for r in read_rows(out)] == [0, 3, 6, 9] and len(dump.agents) == 250
