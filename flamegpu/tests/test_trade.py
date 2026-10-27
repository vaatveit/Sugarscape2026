"""Trade T in the turn (pp.101-107; plan 2026-10-26-gpu-parity-part-c, Task 5).

Trading neighbours are not order-free over a period (each metabolises before it trades), so Python is stepped in the
GPU's own turn order (gpu.period_orders, reference.run_python_in_order). Agents have vision 0 on an empty map, so a
turn is metabolism, then trade.
"""

import math
import random

import numpy as np
import pytest

from conftest import run_exe
from gpu import period_orders, read_rows, run_gpu, write_cfg
from reference import run_python
from test_spice import _registry

EMPTY = np.zeros((20, 20), dtype=int)
TRADE = {"spice": "true", "trade": "true", "vision": "0,0"}
TRADE_COLUMNS = ("trades", "mean_price", "mean_log_price", "price_sd", "sugar_traded", "spice_traded")


def _pairs(n: int, seed: int, tags: int = 0) -> list[dict]:
    """Julia's _pairs (julia/bridge/scenarios.py): fixed random holdings and metabolisms, the pair i at
    (4 (i % 5), 4 (i // 5)) and the site east of it."""
    rng = random.Random(seed)
    agents = []
    for k in range(2 * n):
        i = k // 2
        a = {"x": 4 * (i % 5) + k % 2, "y": 4 * (i // 5), "vision": 0, "metabolism": rng.randint(1, 5),
             "sugar": round(rng.uniform(1, 100), 3), "spice": round(rng.uniform(1, 100), 3),
             "spice_metabolism": rng.randint(1, 5), "age": 0, "max_age": None}
        if tags:
            a["tags"] = "".join(str(rng.randint(0, 1)) for _ in range(tags))
        agents.append(a)
    return agents


def _same(a, b, rel=1e-12):
    if isinstance(a, float) and math.isnan(a):
        return isinstance(b, float) and math.isnan(b)
    return math.isclose(a, b, rel_tol=rel, abs_tol=1e-12)


CASES = {
    "exact": (TRADE, _pairs(15, 11)),
    "down": ({**TRADE, "trade_rounding": "down"}, _pairs(15, 11)),
    "cultural": ({**TRADE, "tag_length": "3", "cultural_preferences": "true"}, _pairs(15, 12, tags=3)),
    # Chapter V (plan 2026-10-27-gpu-parity-part-d, Task 3): everyone carries "111", which no all-0 immune string
    # clears in two periods, so nobody is infected and each burn is 1 higher: welfare and the MRS count the fee.
    "diseased": ({**TRADE, "disease_list": "1", "disease_length": "3,3", "immune_length": "10"},
                 [dict(a, immune="0" * 10, diseases="0") for a in _pairs(15, 11)]),
}
DISEASES = {"diseased": ["111"]}


@pytest.mark.parametrize("name", CASES)
def test_trade_pairs_match_python(exe, tmp_path, name):
    from reference import run_python_in_order

    cfg, agents = CASES[name]
    diseases = DISEASES.get(name)
    orders = period_orders(exe, tmp_path / "order", cfg, EMPTY, agents, 2, diseases=diseases)
    out = tmp_path / "metrics.csv"
    gpu = run_gpu(exe, tmp_path, cfg, EMPTY, agents, steps=2, extra_args=("--out", out), diseases=diseases)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python_in_order(cfg, EMPTY, agents, orders, diseases=diseases)
    g, p = {a["uid"]: a for a in gpu.agents}, {a["uid"]: a for a in py.agents}
    assert set(g) == set(p)
    for uid in p:
        for good in ("sugar", "spice"):
            assert math.isclose(g[uid][good], p[uid][good], abs_tol=1e-9), (name, uid, good, g[uid][good], p[uid][good])
    rows = read_rows(out)
    assert py.csv[1]["trades"] > 0, "the scenario must trade"
    for t in (1, 2):
        for col in TRADE_COLUMNS:
            assert _same(float(rows[t][col]), float(py.csv[t][col])), (name, t, col, rows[t][col], py.csv[t][col])


def test_no_trade_with_zero_spice_metabolism(exe, tmp_path):
    # A spice metabolism of 0 makes the MRS infinite: no trade (Python's _valid), whoever goes first.
    agents = _pairs(1, 11)
    agents[0]["spice_metabolism"] = 0
    out = tmp_path / "metrics.csv"
    gpu = run_gpu(exe, tmp_path, TRADE, EMPTY, agents, steps=1, extra_args=("--out", out))
    assert gpu.returncode == 0, gpu.stderr
    assert read_rows(out)[1]["trades"] == 0
    py = run_python(TRADE, EMPTY, agents, 1)
    g, p = {a["uid"]: a for a in gpu.agents}, {a["uid"]: a for a in py.agents}
    for uid in p:
        assert math.isclose(g[uid]["sugar"], p[uid]["sugar"]) and math.isclose(g[uid]["spice"], p[uid]["spice"])


def test_trade_metrics_t0(exe, tmp_path):
    out = tmp_path / "metrics.csv"
    gpu = run_gpu(exe, tmp_path, TRADE, EMPTY, _pairs(3, 11), steps=1, extra_args=("--out", out))
    assert gpu.returncode == 0, gpu.stderr
    row = read_rows(out)[0]
    assert row["trades"] == 0 and row["sugar_traded"] == 0 and row["spice_traded"] == 0
    assert all(math.isnan(row[c]) for c in ("mean_price", "mean_log_price", "price_sd"))


@pytest.mark.parametrize("exp_id", ["IV-3", "IV-14", "IV-17", "IV-A3"])
def test_serial_equivalence_trade(exe, tmp_path, exp_id):
    from test_sex import _files

    cfg = _registry(exp_id)
    assert _files(exe, tmp_path / "waves", cfg, 20) == _files(exe, tmp_path / "serial", cfg, 20, "--serial-turns")
    assert read_rows(tmp_path / "waves" / "metrics.csv")[-1]["trades"] > 0


@pytest.mark.parametrize("exp_id", ["IV-3", "IV-17"])
def test_trade_check(exe, tmp_path, exp_id):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **_registry(exp_id), steps="20"), "--check")
    assert result.returncode == 0, result.stderr
