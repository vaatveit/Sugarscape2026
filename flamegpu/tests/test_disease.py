"""Chapter V on the GPU (spec 2026-10-25-gpu-full-parity, Part D; plan 2026-10-27-gpu-parity-part-d): immune systems,
the master disease list, rule E, the disease fee and disease_metrics."""

import json
import math

import pytest

from conftest import run_exe
from gpu import read_rows, run_gpu, write_cfg
from reference import python_metric_rows, run_python
from sugarscape.rules.disease import is_immune
from test_parity import CAPACITY
from test_spice import _registry

DISEASE_STATE = ("mean_diseases", "sd_diseases", "fraction_sick", "diseases_circulating")


def _bits(text) -> str:
    """A 0/1 string read back from a dump (read_rows reads a bare column of digits as a number)."""
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
