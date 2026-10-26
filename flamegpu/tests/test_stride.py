"""look_stride (docs/xl.md, "Looking"; xl design, section 2a): one random look for each whole stride of vision, centred
on it (Python's look_distances: stride * (k + 1) + U{0..s-1} - U{0..s-1}, each distance looked at once), vision in
whole strides.

Exact parity with Python is impossible above stride 1, since the draws differ, so these tests check the rule's
properties. Stride 1 is the regular rule, pinned by the golden runs and the parity tests.
"""

import math
from collections import Counter

import numpy as np

from conftest import run_exe
from gpu import run_gpu, write_cfg, write_map

SPACING_X, SPACING_Y = 50, 2  # vision 10 at stride 10 looks up to 19 sites away, so no agent sees another's food


def test_vision_drawn_in_whole_strides(exe, tmp_path):
    cfg = {"initial_population": "2000", "vision": "10,60", "look_stride": "10"}
    dump = run_gpu(exe, tmp_path, cfg, np.zeros((140, 140), dtype=int), steps=1, dump_at=0)
    assert dump.returncode == 0, dump.stderr
    assert {a["vision"] for a in dump.agents} == {10, 20, 30, 40, 50, 60}


def _east_stretch_run(exe, tmp_path, stride: int, seed: str, food=range(1, 11), vision=10,
                      spacing_x=SPACING_X, width=250) -> Counter:
    """Agents spaced spacing_x apart along x, each with capacity 4 on the sites east of it at the given distances
    and nothing else in view: how far each moved."""
    capacity = np.zeros((width, 100), dtype=int)
    agents = []
    for x in range(0, width, spacing_x):
        for y in range(0, 100, SPACING_Y):
            for d in food:
                capacity[x + d, y] = 4
            agents.append({"x": x, "y": y, "vision": vision, "metabolism": 1, "sugar": 50.0, "age": 0,
                           "max_age": None})
    cfg = {"vision": f"{vision},{vision}", "look_stride": str(stride), "seed": seed}
    dump = run_gpu(exe, tmp_path, cfg, capacity, agents, steps=1)
    assert dump.returncode == 0, dump.stderr
    assert len(dump.agents) == len(agents)
    return Counter(a["x"] % spacing_x for a in dump.agents)  # the distance moved east (0: stayed)


def _within(count: int, n: int, p: float) -> bool:
    return abs(count - n * p) <= 4 * math.sqrt(n * p * (1 - p)) + 3


def test_look_is_centred_on_the_stride(exe, tmp_path):
    # Vision 10 is one look, at 10 + a - b with a, b uniform on 0..9: food on every site 1..19 east, so each agent
    # moves to the one it saw. Distance d comes up with probability (10 - |d - 10|) / 100.
    moved = Counter()
    for seed in ("1", "2", "3", "4"):
        (tmp_path / seed).mkdir()
        moved += _east_stretch_run(exe, tmp_path / seed, 10, seed, food=range(1, 20))
    n = sum(moved.values())
    assert set(moved) == set(range(1, 20)), moved
    assert all(_within(moved[d], n, (10 - abs(d - 10)) / 100) for d in range(1, 20)), moved


def test_second_look_is_centred_on_twice_the_stride(exe, tmp_path):
    # Vision 20 is two looks: 10 + a - b (1..19) and 20 + a - b (11..29). Food only on 20..29 east, which only the
    # second look reaches, when a >= b (55%): it lands on 20 + j with probability (10 - j) / 100. 60 apart, 300
    # wide: at reach 29 no agent sees another's food.
    moved = Counter()
    for seed in ("1", "2", "3", "4"):
        (tmp_path / seed).mkdir()
        moved += _east_stretch_run(exe, tmp_path / seed, 10, seed, food=range(20, 30), vision=20, spacing_x=60,
                                   width=300)
    n = sum(moved.values())
    assert set(moved) == {0, *range(20, 30)}, moved
    assert _within(moved[0], n, 0.45), moved
    assert all(_within(moved[20 + j], n, (10 - j) / 100) for j in range(10)), moved


def test_partner_seen_twice_is_one_partner(exe, tmp_path):
    # Vision 20 at stride 10: the two looks along a line overlap on 11..19, so a partner 15 sites away can come up
    # in both. Python looks at each distance once (a set), so a pair has at most two children in a period, one in each
    # parent's turn. 200 isolated pairs (rows 30 apart, pairs 60 apart: nobody else within reach 29), 10 seeds.
    capacity = np.zeros((600, 600), dtype=int)
    parent = {"vision": 20, "metabolism": 0, "sugar": 1000.0, "initial_sugar": 50.0, "age": 20, "max_age": None,
              "fertility_start": 12}
    agents = []
    for y in range(0, 600, 30):
        for x in range(0, 600, 60):
            agents += [{"x": x, "y": y, "sex": "F", "fertility_end": 50, **parent},
                       {"x": x + 15, "y": y, "sex": "M", "fertility_end": 60, **parent}]
    cfg = {"sex": "true", "mate_contact": "vision", "vision": "20,20", "look_stride": "10", "max_age": "60,100"}
    children = Counter()
    for seed in range(10):
        (tmp_path / str(seed)).mkdir()
        dump = run_gpu(exe, tmp_path / str(seed), {**cfg, "seed": str(seed)}, capacity, agents, steps=1)
        assert dump.returncode == 0, dump.stderr
        children.update(a["n_children"] for a in dump.agents if a["sex"] == "F" and a["age"] == 21)
    assert max(children) <= 2, children
    assert children[2] > 0, children  # each parent saw the other in its own turn


def test_vision_reach_counts_the_stride(exe, tmp_path):
    # Python's Config: with a look stride s the farthest look is s - 1 sites past vision, and twice that reach must
    # be less than the grid. Vision 20 at stride 10 reaches 29: a 58-wide grid is too small, 60 is enough.
    def run(size):
        world = write_map(tmp_path / f"map{size}.txt", [[0] * size for _ in range(size)])
        cfg = write_cfg(tmp_path, map=str(world), width=str(size), height=str(size), vision="10,20", look_stride="10",
                        initial_population="10")
        return run_exe(exe, "--config", cfg, "--print-config")
    result = run(58)
    assert result.returncode == 2
    assert "max vision 20 (looking up to 29 sites away) must be less than half the grid (58x58)" in result.stderr
    assert run(60).returncode == 0


def test_stride_one_looks_at_every_site(exe, tmp_path):
    # The control: seeing every site, every agent takes the nearest food, 1 site away.
    assert _east_stretch_run(exe, tmp_path, 1, "1") == Counter({1: 250})
