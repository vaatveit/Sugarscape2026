"""Chapter V on the GPU (spec 2026-10-25-gpu-full-parity, Part D; plan 2026-10-27-gpu-parity-part-d): immune systems,
the master disease list, rule E, the disease fee and disease_metrics."""

import json
import math

import numpy as np
import pytest

from conftest import run_exe
from gpu import compare_dumps, period_orders, read_rows, run_gpu, write_cfg
from reference import python_metric_rows, run_python, run_python_in_order
from sugarscape.rules.disease import is_immune
from test_parity import CAPACITY
from test_spice import _registry

DISEASE_STATE = ("mean_diseases", "sd_diseases", "fraction_sick", "diseases_circulating")


def _bits(text) -> str:
    """A 0/1 string or disease list read back from a dump: the columns are TEXT_COLUMNS, so only None becomes ""."""
    return "" if text is None else str(text)


# --- Task 2: the master list, immune systems, founders' infections ------------------------------------------------


def test_master_list_draws(exe, tmp_path):
    # 2 one-bit and 4 two-bit strings: twenty draws must repeat one.
    out = tmp_path / "diseases.csv"
    cfg = {"disease_list": "20", "disease_length": "1,2", "immune_length": "10"}
    dump = run_gpu(exe, tmp_path, cfg, CAPACITY, steps=1, dump_at=0, extra_args=("--dump-diseases", out))
    assert dump.returncode == 0, dump.stderr
    with out.open() as f:
        rows = [line.rstrip("\n").split(",") for line in f][1:]
    assert [int(r[0]) for r in rows] == list(range(20))
    bits = [r[2] for r in rows]
    assert all(len(b) in (1, 2) and set(b) <= {"0", "1"} for b in bits)
    for i, (_, canonical, b) in enumerate(rows):
        assert int(canonical) == bits.index(b), (i, canonical, b)
    assert len(set(bits)) < 20


def _master_bits(path) -> list[tuple[int, ...]]:
    """--dump-diseases' bits column (index, canonical, bits per master entry)."""
    with path.open() as f:
        return [tuple(int(c) for c in line.rstrip("\n").split(",")[2]) for line in list(f)[1:]]


@pytest.mark.parametrize("per_agent", [0, 4], ids=["none", "four"])
def test_founders_infected(exe, tmp_path, per_agent):
    out = tmp_path / "diseases.csv"
    cfg = {"disease_list": "10", "diseases_per_agent": str(per_agent), "immune_length": "50"}
    dump = run_gpu(exe, tmp_path, cfg, CAPACITY, steps=1, dump_at=0, extra_args=("--dump-diseases", out))
    assert dump.returncode == 0, dump.stderr
    master = _master_bits(out)
    assert len(dump.agents) == 400
    carriers = 0
    for a in dump.agents:
        immune, genotype = _bits(a["immune"]), _bits(a["immune_genotype"])
        assert len(immune) == 50 and immune == genotype
        ids = [int(i) for i in str(a["diseases"] or "").split("|") if i != ""]
        assert len(ids) == len(set(ids)) <= per_agent
        for i in ids:
            assert master.index(master[i]) == i  # canonical
            assert not is_immune([int(c) for c in immune], master[i])
        carriers += bool(ids)
    assert (carriers > 0) == (per_agent > 0)


def test_newcomers_draw_immune(exe, tmp_path):
    cfg = {"replacement": "true", "max_age": "1,1", "initial_population": "100", "disease_list": "10",
           "diseases_per_agent": "4"}
    dump = run_gpu(exe, tmp_path, cfg, CAPACITY, steps=3)
    assert dump.returncode == 0, dump.stderr
    assert dump.agents and all(a["uid"] >= 100 for a in dump.agents)
    strings = set()
    for a in dump.agents:
        immune = _bits(a["immune"])
        assert len(immune) == 50 and immune == _bits(a["immune_genotype"])
        assert _bits(a["diseases"]) == ""
        strings.add(immune)
    assert len(strings) > 1


def test_child_genotype_crossed(exe, tmp_path):
    from test_sex import BOOK, CFG, EMPTY, PAIR

    agents = [dict(a, immune="0" * 10) for a in PAIR]
    agents[0].update(immune_genotype="0000011111", immune="1111111111")  # F
    agents[1].update(immune_genotype="0000000000", immune="1111100000")  # M
    cfg = {**CFG, **BOOK, "disease_list": "1", "disease_length": "1,2", "immune_length": "10"}
    dump = run_gpu(exe, tmp_path, cfg, EMPTY, agents, steps=1, diseases=["11"])
    assert dump.returncode == 0, dump.stderr
    child = next(a for a in dump.agents if a["uid"] == len(agents))
    genotype = _bits(child["immune_genotype"])
    assert genotype[:5] == "00000"  # the genotypes agree there; the immune strings would give 11111
    assert _bits(child["immune"]) == genotype
    assert all(_bits(a["diseases"]) == "" for a in dump.agents)


ROUND_TRIP_LIST = ["101", "0110", "101", "1"]  # index 2 is index 0's string


def _round_trip_agents():
    sites = ((2, 2), (12, 2), (2, 12), (12, 12))
    carried = ("0|3", "", "2", "3|1")
    return [{"x": x, "y": y, "vision": 1, "metabolism": 1, "sugar": 10.0, "age": 0, "max_age": None,
             "immune": "0" * 12, "diseases": d} for (x, y), d in zip(sites, carried)]


ROUND_TRIP_CFG = {"disease_list": "4", "immune_length": "12"}


def test_disease_dump_round_trip(exe, tmp_path):
    agents = _round_trip_agents()
    gpu = run_gpu(exe, tmp_path, ROUND_TRIP_CFG, CAPACITY, agents, steps=1, dump_at=0, diseases=ROUND_TRIP_LIST)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(ROUND_TRIP_CFG, CAPACITY, agents, 0, diseases=ROUND_TRIP_LIST)
    key = lambda a: (a["x"], a["y"])  # noqa: E731
    g = {key(a): a for a in gpu.agents}
    p = {key(a): a for a in py.agents}
    assert set(g) == set(p)
    for k in p:
        for column in ("immune_genotype", "immune", "diseases"):
            assert _bits(g[k][column]) == _bits(p[k][column]), (k, column, g[k][column], p[k][column])
    assert _bits(g[(2, 12)]["diseases"]) == "0" == _bits(p[(2, 12)]["diseases"])


def _init_refused(exe, tmp_path, cfg, agents, diseases=None):
    result = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=1, diseases=diseases)
    assert result.returncode == 2, result.stderr
    return result.stderr


@pytest.mark.parametrize("case", ["columns-without-disease", "no-immune", "duplicate", "list-count", "list-too-long"])
def test_init_disease_refused(exe, tmp_path, case):
    agents = _round_trip_agents()
    cfg, diseases = dict(ROUND_TRIP_CFG), list(ROUND_TRIP_LIST)
    if case == "columns-without-disease":
        cfg, diseases = {}, None
        named = "disease_list = 0"
    elif case == "no-immune":
        agents[1]["immune"] = None
        named = "line 3"
    elif case == "duplicate":
        agents[1]["diseases"] = "0|2"  # two indices of one string, which Python's infect never gives
        named = "line 3"
    elif case == "list-count":
        diseases = diseases[:3]
        named = "diseases.txt"
    else:
        diseases[3] = "1" * 12  # not shorter than the immune system
        named = "diseases.txt"
    stderr = _init_refused(exe, tmp_path, cfg, agents, diseases)
    assert named in stderr.splitlines()[0], stderr


def test_disease_metrics_t0_match_python(exe, tmp_path):
    agents = _round_trip_agents()
    out = tmp_path / "metrics.csv"
    gpu = run_gpu(exe, tmp_path, ROUND_TRIP_CFG, CAPACITY, agents, steps=1, diseases=ROUND_TRIP_LIST,
                  extra_args=("--out", out))
    assert gpu.returncode == 0, gpu.stderr
    g = read_rows(out)[0]
    p = python_metric_rows(ROUND_TRIP_CFG, CAPACITY, agents, 0, diseases=ROUND_TRIP_LIST)[0]
    for name in DISEASE_STATE:
        assert math.isclose(g[name], p[name], rel_tol=1e-12), (name, g[name], p[name])
    assert g["diseases_circulating"] == 3  # indices 0 and 2 are one string


def test_disease_check(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **_registry("V-2"), steps="5"), "--check")
    assert result.returncode == 0, result.stderr


def test_disease_runs_on_turns(exe, tmp_path):
    timing = tmp_path / "timing.json"
    result = run_exe(exe, "--config", write_cfg(tmp_path, **_registry("V-1"), steps="1"), "--timing", timing)
    assert result.returncode == 0, result.stderr
    assert json.loads(timing.read_text())["waves_mean"] > 0


# --- Task 3: rule E in the turn, the disease fee, new infections --------------------------------------------------

FEE_LIST = ["111", "0110", "1", "10101"]  # "1" is cleared in period 1, the others later
FEE_CASES = {
    "plain": {},
    "polluted": {"pollution": "1.0,1.0", "diffusion_period": "1"},
    "welfare": {"spice": "true"},
}


def _fee_agents(spice: bool) -> list[dict]:
    from test_spice import _movers

    carried = ("", "2", "0|1", "0|2|3")  # 0, 1, 2 and 3 diseases
    agents = [dict(a, immune="0" * 12, diseases=d) for a, d in zip(_movers(sugar=40.0), carried)]
    if not spice:
        for a in agents:
            del a["spice"], a["spice_metabolism"]
    return agents


@pytest.mark.parametrize("name", FEE_CASES)
def test_disease_fee_matches_python(exe, tmp_path, name):
    # Python steps in the GPU's order: under welfare two agents reach for one site at t = 2.
    cfg = {"disease_list": "4", "immune_length": "12", **FEE_CASES[name]}
    agents = _fee_agents(name == "welfare")
    orders = period_orders(exe, tmp_path / "order", cfg, CAPACITY, agents, 4, diseases=FEE_LIST)
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=4, diseases=FEE_LIST)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python_in_order(cfg, CAPACITY, agents, orders, diseases=FEE_LIST)
    assert compare_dumps(gpu, py, pollution=True) == []
    assert len(py.agents) == 4


def _welfare_choice_capacity():
    # Spice capacity is the sugar map mirrored east-west: the site east of (3,3) holds 10 sugar, the site west 10 spice.
    capacity = np.zeros((7, 7), dtype=int)
    capacity[4, 3] = 10
    return capacity


def test_fee_steers_welfare_movement(exe, tmp_path):
    # With equal holdings the agent takes sugar iff its sugar burn outweighs its spice metabolism (eq. 1): two diseases
    # make the burn 3 against 2, so it goes east; scored on its metabolism alone (1) it would go west.
    cfg = {"spice": "true", "vision": "1,1", "disease_list": "2", "immune_length": "12"}
    agents = [{"x": 3, "y": 3, "vision": 1, "metabolism": 1, "sugar": 20.0, "spice": 20.0, "spice_metabolism": 2,
               "age": 0, "max_age": None, "immune": "0" * 12, "diseases": "0|1"}]
    capacity = _welfare_choice_capacity()
    gpu = run_gpu(exe, tmp_path, cfg, capacity, agents, steps=1, diseases=STARVE_LIST)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, capacity, agents, 1, diseases=STARVE_LIST)
    assert compare_dumps(gpu, py) == []
    assert (gpu.agents[0]["x"], gpu.agents[0]["y"]) == (4, 3)


STARVE_LIST = ["111", "0110"]


def _starve_agents():
    still = {"vision": 0, "age": 0, "max_age": None}
    return [{"x": 3, "y": 3, "metabolism": 1, "sugar": 3.0, "immune": "0" * 12, "diseases": "0|1", **still},  # burns 3
            {"x": 3, "y": 4, "metabolism": 0, "sugar": 50.0, "immune": "111011000000", **still}]  # immune to both


def test_fee_starvation_matches_python(exe, tmp_path):
    empty = np.zeros((7, 7), dtype=int)
    agents = _starve_agents()
    firsts = set()
    for seed in range(10):
        cfg = {"vision": "0,0", "disease_list": "2", "immune_length": "12", "seed": str(seed)}
        tmp = tmp_path / str(seed)
        orders = period_orders(exe, tmp / "order", cfg, empty, agents, 1, diseases=STARVE_LIST)
        gpu = run_gpu(exe, tmp, cfg, empty, agents, steps=1, diseases=STARVE_LIST)
        assert gpu.returncode == 0, gpu.stderr
        py = run_python_in_order(cfg, empty, agents, orders, diseases=STARVE_LIST)
        assert compare_dumps(gpu, py) == [], seed
        assert len(gpu.agents) == len(py.agents) == 1, seed  # S starves of its fee
        assert gpu.agents[0]["neighbors"] == py.agents[0]["neighbors"], seed
        firsts.add(orders[0][0])
    assert firsts == {0, 1}, "both orders must occur"


def test_immune_response_matches_python(exe, tmp_path):
    diseases = ["111", "1", "0110"]
    cfg = {"disease_list": "3", "immune_length": "12"}
    agents = [{"x": 2, "y": 2, "vision": 1, "metabolism": 1, "sugar": 40.0, "age": 0, "max_age": None,
               "immune": "0" * 12, "diseases": "0|1|2"}]
    counts = []
    for t in range(1, 5):
        (tmp_path / str(t)).mkdir()
        gpu = run_gpu(exe, tmp_path / str(t), cfg, CAPACITY, agents, steps=t, diseases=diseases)
        assert gpu.returncode == 0, gpu.stderr
        py = run_python(cfg, CAPACITY, agents, t, diseases=diseases)
        assert compare_dumps(gpu, py) == [], t
        counts.append(len([d for d in _bits(gpu.agents[0]["diseases"]).split("|") if d]))
    assert counts[-1] < counts[0], counts


def test_disease_limits_match_python(exe, tmp_path):
    # Part D's final review, minor 3: the GPU's limits themselves, a 64-bit immune system and a 64-entry list, its
    # last entry a 63-bit disease. Every string is distinct, so every id is canonical.
    diseases = [format(i, "06b") for i in range(63)] + ["1" * 63]
    cfg = {"disease_list": "64", "disease_length": "1,63", "immune_length": "64"}
    agents = [{"x": 2, "y": 2, "vision": 1, "metabolism": 1, "sugar": 40.0, "age": 0, "max_age": None,
               "immune": "0" * 64, "diseases": "63|5"}]
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=3, diseases=diseases)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, CAPACITY, agents, 3, diseases=diseases)
    assert compare_dumps(gpu, py) == []
    assert "63" in _bits(gpu.agents[0]["diseases"]).split("|")  # 63 bits from all 0: not cleared in 3 periods


TRANSMIT_LIST = ["0110", "0110", "111"]  # index 1 is index 0's string
TRANSMIT_CFG = {"vision": "0,0", "disease_list": "3", "immune_length": "12"}
TRANSMIT_INFECTIONS = {"susceptible": 15, "immune": 0, "duplicate": 0}


def _transmit_agents(case: str) -> list[dict]:
    """15 pairs at (4 (i % 5), 4 (i // 5)) and the site east of it: the source carries index 0."""
    agents = []
    for i in range(15):
        x, y = 4 * (i % 5), 4 * (i // 5)
        still = {"y": y, "vision": 0, "metabolism": 0, "sugar": 50.0, "age": 0, "max_age": None}
        agents.append({"x": x, "immune": "0" * 12, "diseases": "0", **still})
        partner = {"x": x + 1, "immune": "0" * 12, **still}
        if case == "immune":
            partner["immune"] = "011000000000"  # holds 0110
        elif case == "duplicate":
            partner["diseases"] = "1"  # the same string under another index
        agents.append(partner)
    return agents


@pytest.mark.parametrize("case", TRANSMIT_INFECTIONS)
def test_transmission_matches_python(exe, tmp_path, case):
    empty = np.zeros((20, 20), dtype=int)
    agents = _transmit_agents(case)
    for seed in range(5):
        cfg = {**TRANSMIT_CFG, "seed": str(seed)}
        tmp = tmp_path / str(seed)
        orders = period_orders(exe, tmp / "order", cfg, empty, agents, 1, diseases=TRANSMIT_LIST)
        out = tmp / "metrics.csv"
        gpu = run_gpu(exe, tmp, cfg, empty, agents, steps=1, diseases=TRANSMIT_LIST, extra_args=("--out", out))
        assert gpu.returncode == 0, gpu.stderr
        py = run_python_in_order(cfg, empty, agents, orders, diseases=TRANSMIT_LIST)
        assert compare_dumps(gpu, py) == [], (case, seed)
        g = read_rows(out)[1]
        assert g["new_infections"] == py.csv[1]["new_infections"] == TRANSMIT_INFECTIONS[case], (case, seed)
        for name in DISEASE_STATE:
            assert math.isclose(g[name], py.csv[1][name], rel_tol=1e-12), (case, seed, name)
        rank = {uid: i for i, uid in enumerate(orders[0])}
        assert {rank[2 * i] < rank[2 * i + 1] for i in range(15)} == {True, False}, "both orders must occur"


def test_newborn_infected_in_birth_period(exe, tmp_path):
    from test_sex import BOOK, CFG, EMPTY, PAIR

    agents = [dict(a, immune="1100000000") for a in PAIR]  # immune to "11"
    for parent in agents[:2]:
        parent["immune_genotype"] = "0000000000"  # so the child is not
    carrier = next(i for i, a in enumerate(agents) if (a["x"], a["y"]) == (6, 6))  # next to the child's site, (5,6)
    agents[carrier].update(immune="0" * 10, diseases="0")
    cfg = {**CFG, **BOOK, "disease_list": "1", "disease_length": "2,2", "immune_length": "10"}
    outcomes = set()
    for seed in range(10):
        run = {**cfg, "seed": str(seed)}
        tmp = tmp_path / str(seed)
        orders = period_orders(exe, tmp / "order", run, EMPTY, agents, 1, diseases=["11"])
        gpu = run_gpu(exe, tmp, run, EMPTY, agents, steps=1, diseases=["11"])
        assert gpu.returncode == 0, gpu.stderr
        py = run_python_in_order(run, EMPTY, agents, orders, diseases=["11"])
        assert compare_dumps(gpu, py) == [], seed
        child = next(a for a in gpu.agents if a["uid"] == len(agents))
        rank = {uid: i for i, uid in enumerate(orders[0])}
        infected = _bits(child["diseases"]) == "0"
        assert infected == (rank[carrier] > min(rank[0], rank[1])), seed  # the carrier's turn follows the mating
        outcomes.add(infected)
    assert outcomes == {True, False}, "both outcomes must occur"


@pytest.mark.parametrize("exp_id", ["V-2", "VI-1"])
def test_serial_equivalence_disease(exe, tmp_path, exp_id):
    from test_sex import _files

    cfg = _registry(exp_id)
    assert _files(exe, tmp_path / "waves", cfg, 20) == _files(exe, tmp_path / "serial", cfg, 20, "--serial-turns")
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg, steps="20"), "--check")
    assert result.returncode == 0, result.stderr


def test_disease_metrics_match_python(exe, tmp_path):
    empty = np.zeros((20, 20), dtype=int)
    agents = _transmit_agents("susceptible")
    orders = period_orders(exe, tmp_path / "order", TRANSMIT_CFG, empty, agents, 1, diseases=TRANSMIT_LIST)
    out = tmp_path / "metrics.csv"
    gpu = run_gpu(exe, tmp_path, TRANSMIT_CFG, empty, agents, steps=1, diseases=TRANSMIT_LIST,
                  extra_args=("--out", out))
    assert gpu.returncode == 0, gpu.stderr
    py = run_python_in_order(TRANSMIT_CFG, empty, agents, orders, diseases=TRANSMIT_LIST)
    rows = read_rows(out)
    for t in (0, 1):
        for name in (*DISEASE_STATE, "new_infections"):
            assert math.isclose(rows[t][name], py.csv[t][name], rel_tol=1e-12), (t, name, rows[t][name], py.csv[t][name])
