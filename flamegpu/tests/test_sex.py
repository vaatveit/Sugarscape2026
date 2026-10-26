"""Rule S in the turn (spec 2026-10-25-gpu-full-parity, section 4; Part A, Task 5).

Parity scenarios: nobody can move (every capacity 0, or vision 0), one fertile F/M pair, and exactly one empty site
next to either parent. Whichever parent comes first has the child and neither can have another, so Python's random
order cannot matter. Parents share vision, metabolism and maximum age, so the child's genes cannot depend on the draws.
"""

import math

import numpy as np
import pytest

from conftest import run_exe
from gpu import read_rows, run_gpu, write_cfg
from reference import run_python

EMPTY = np.zeros((20, 20), dtype=int)
CFG = {"sex": "true", "max_age": "60,100", "endowment": "50,100", "vision": "1,6"}


def _parent(x, y, sex, **kw):
    return {"x": x, "y": y, "vision": 0, "metabolism": 1, "sugar": 60.0, "age": 20, "max_age": 90, "sex": sex,
            "fertility_start": 12, "fertility_end": 45 if sex == "F" else 55, "initial_sugar": 50.0, **kw}


def _blocker(x, y):
    return {"x": x, "y": y, "vision": 0, "metabolism": 1, "sugar": 100.0, "age": 20, "max_age": 90}


# F at (5,5) and M at (6,5): every site around them is blocked except (5,6).
PAIR = [_parent(5, 5, "F"), _parent(6, 5, "M")] + [_blocker(x, y) for x, y in ((4, 5), (5, 4), (7, 5), (6, 6), (6, 4))]
# Partners in sight (candidate C1): M three sites east of F, both with vision 3; only (5,6) is empty around either.
SIGHT = ([_parent(5, 5, "F", vision=3), _parent(8, 5, "M", vision=3)] +
         [_blocker(x, y) for x, y in ((6, 5), (4, 5), (5, 4), (9, 5), (7, 5), (8, 6), (8, 4))])

BOOK = {"mate_contact": "neighbors", "gift_rounding": "exact"}
CASES = {
    "book": (BOOK, PAIR),
    "intgift": ({"mate_contact": "neighbors", "gift_rounding": "down"},
                [dict(a, initial_sugar=51.0) if a.get("sex") else a for a in PAIR]),
    "c1": ({"mate_contact": "vision", "gift_rounding": "exact"}, SIGHT),
    "capped": ({**BOOK, "child_gift": "capped"}, PAIR),
    "redraw": ({**BOOK, "child_threshold": "redraw"}, PAIR),
    "threshold": ({**BOOK, "fertility_threshold": "0.74"}, [dict(a, sugar=41.0) if a.get("sex") else a for a in PAIR]),
}


def _by_uid(agents):
    return {a["uid"]: a for a in agents}


@pytest.mark.parametrize("name", CASES)
def test_mating_matches_python(exe, tmp_path, name):
    over, agents = CASES[name]
    cfg = {**CFG, **over}
    gpu = run_gpu(exe, tmp_path, cfg, EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, EMPTY, agents, 1)
    for seed in ("1", "2"):  # the scenario must not depend on Python's order
        other = run_python({**cfg, "seed": seed}, EMPTY, agents, 1)
        assert [(a["x"], a["y"], a["sugar"]) for a in other.agents] == [(a["x"], a["y"], a["sugar"]) for a in py.agents]
    g, p = _by_uid(gpu.agents), _by_uid(py.agents)
    assert set(g) == set(p) and len(p) == len(agents) + 1  # one child
    child = len(agents)
    for uid, pa in p.items():
        ga = g[uid]
        for key in ("x", "y", "vision", "metabolism", "age", "max_age", "n_children"):
            assert ga[key] == pa[key], (name, uid, key, ga[key], pa[key])
        assert math.isclose(ga["sugar"], pa["sugar"], abs_tol=1e-9), (name, uid, ga["sugar"], pa["sugar"])
        if uid != child or name != "redraw":
            assert math.isclose(ga["initial_sugar"], pa["initial_sugar"], abs_tol=1e-9), (name, uid)
    assert g[child]["sex"] in ("F", "M")
    assert 12 <= g[child]["fertility_start"] <= 15
    assert {g[child]["parent_a"], g[child]["parent_b"]} == {0, 1}
    if name == "redraw":
        assert 50 <= g[child]["initial_sugar"] <= 100 and g[child]["initial_sugar"] == int(g[child]["initial_sugar"])


def test_children_aged_in_birth_period(exe, tmp_path):
    over, agents = CASES["book"]
    gpu = run_gpu(exe, tmp_path, {**CFG, **over}, EMPTY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    assert _by_uid(gpu.agents)[len(agents)]["age"] == 1


def test_no_birth_without_empty_site(exe, tmp_path):
    agents = PAIR + [_blocker(5, 6)]
    gpu = run_gpu(exe, tmp_path, {**CFG, **BOOK}, EMPTY, agents, steps=2)
    assert gpu.returncode == 0, gpu.stderr
    assert len(gpu.agents) == len(agents) and all(a["n_children"] == 0 for a in gpu.agents)


def test_child_never_on_pending_target(exe, tmp_path):
    # Difference 2 of the spec: C, with vision 2, targets (5,6), the only empty site next to the pair. A child is never
    # born there, whatever the order, and C always arrives.
    capacity = EMPTY.copy()
    capacity[5, 6] = 4
    seeker = {"x": 5, "y": 8, "vision": 2, "metabolism": 1, "sugar": 100.0, "age": 20, "max_age": 90}
    agents = PAIR + [seeker]
    for seed in range(20):
        (tmp_path / str(seed)).mkdir()
        gpu = run_gpu(exe, tmp_path / str(seed), {**CFG, **BOOK, "seed": str(seed)}, capacity, agents, steps=1)
        assert gpu.returncode == 0, gpu.stderr
        assert len(gpu.agents) == len(agents), seed
        at = {(a["x"], a["y"]): a for a in gpu.agents}
        assert at[(5, 6)]["vision"] == 2, seed


III_1 = {"sex": "true", "max_age": "60,100", "endowment": "50,100"}
BLOCK = {"placement": "block", "block": "0,0,20,20", "initial_population": "400"}
SERIAL_CASES = {
    "block_vision": {**III_1, **BLOCK},
    "neighbors": {**III_1, **BLOCK, "mate_contact": "neighbors"},
    "stride5": {**III_1, **BLOCK, "vision": "5,20", "look_stride": "5"},
}


def _files(exe, tmp, cfg, steps, *extra):
    tmp.mkdir(parents=True, exist_ok=True)
    result = run_exe(exe, "--config", write_cfg(tmp, **cfg, steps=str(steps)), "--out", tmp / "metrics.csv",
                     "--dump-agents", tmp / "agents.csv", "--dump-landscape", tmp / "landscape.csv",
                     "--dump-at", str(steps), *extra)
    assert result.returncode == 0, result.stderr
    out = {}
    for f in ("metrics.csv", "agents.csv", "landscape.csv"):
        lines = (tmp / f).read_text().splitlines()
        if f == "agents.csv":  # FLAME GPU numbers newborns in thread order; uids follow Python's creation order
            drop = lines[0].split(",").index("id")
            lines = [",".join(v for i, v in enumerate(line.split(",")) if i != drop) for line in lines]
        out[f] = lines
    return out


@pytest.mark.parametrize("name", SERIAL_CASES)
def test_serial_equivalence(exe, tmp_path, name):
    waves = _files(exe, tmp_path / "waves", SERIAL_CASES[name], 20)
    serial = _files(exe, tmp_path / "serial", SERIAL_CASES[name], 20, "--serial-turns")
    assert waves == serial
    births = read_rows(tmp_path / "waves" / "metrics.csv")[-1]["agents_ever"] - 400
    assert births > 0, "the scenario must have births to test"


@pytest.mark.parametrize("name", SERIAL_CASES)
def test_footprints_complete_under_check(exe, tmp_path, name):
    # --check makes every turn look up each site it touches in its own footprint (store.h, touch()): exit 3 on a miss.
    # Agents outside childbearing age once scanned their sight lines, which their footprints rightly leave out.
    cfg = {**SERIAL_CASES[name], **({"vision": "3,3"} if name == "block_vision" else {}), "steps": "30"}
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg), "--check")
    assert result.returncode == 0, result.stderr


def test_turns_replacement_check(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **III_1, replacement="true", steps="40"), "--check")
    assert result.returncode == 0, result.stderr


def test_full_world_births_after_starvation(exe, tmp_path):
    # Final review, Important 1: a full 10x10 world where half the agents starve while fertile pairs breed onto the
    # sites they free. Rows in use reach citizens + newborns, beyond the world's cells; the store must hold them.
    full = {"width": "10", "height": "10", "vision": "1,2", "sex": "true", "max_age": "60,100",
            "initial_population": "100", "steps": "3"}
    agents = []
    for x in range(10):
        for y in range(10):
            if (x + y) % 2:  # starves in period 1
                agents.append({"x": x, "y": y, "vision": 0, "metabolism": 500, "sugar": 1.0, "age": 20, "max_age": 90})
            else:
                # Vision 2: partners in sight two sites away along a line (nobody moves: every capacity is 0).
                agents.append({"x": x, "y": y, "vision": 2, "metabolism": 1, "sugar": 100.0, "age": 20, "max_age": 90,
                               "sex": "F" if x % 4 == 0 else "M", "fertility_start": 12, "fertility_end": 55,
                               "initial_sugar": 10.0})
    out = tmp_path / "metrics.csv"
    dump = run_gpu(exe, tmp_path, full, np.zeros((10, 10), dtype=int), agents, steps=3,
                   extra_args=("--out", out, "--check"))
    assert dump.returncode == 0, dump.stderr
    assert read_rows(out)[-1]["agents_ever"] > 100  # children were born on the freed sites


def test_newborn_parents_keep_genealogy(exe, tmp_path):
    # Final review, Minor 1 re-graded: with fertility from age 0 a newborn can be a partner in its birth period. Its
    # child must still name both parents, and its own n_children must count that child.
    cfg = {**III_1, **BLOCK, "fertility_start": "0,0"}
    dump = run_gpu(exe, tmp_path, cfg, steps=6)
    assert dump.returncode == 0, dump.stderr
    born = [a for a in dump.agents if a["uid"] >= 400]
    assert born, "the scenario must have births"
    assert all(a["parent_a"] is not None and a["parent_b"] is not None for a in born)
    living = {}
    for a in dump.agents:
        for p in (a["parent_a"], a["parent_b"]):
            if p is not None:
                living[p] = living.get(p, 0) + 1
    by_uid = _by_uid(dump.agents)
    assert all(by_uid[p]["n_children"] >= k for p, k in living.items() if p in by_uid)


def test_uid_capacity_exceeded(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **III_1, steps="100"), "--uid-capacity", "450")
    assert result.returncode == 5, result.stderr
    assert "uid capacity" in result.stderr
