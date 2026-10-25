"""look_stride (docs/xl.md, "Looking"; xl design, section 2a): one random look per stretch, vision in whole strides.

Exact parity with Python is impossible above stride 1, since the draws differ, so these tests check the rule's
properties. Stride 1 is the regular rule, pinned by the golden runs and the parity tests.
"""

from collections import Counter

import numpy as np

from gpu import run_gpu

SPACING_X, SPACING_Y = 25, 2  # agents see 10 sites, so no agent sees another's food


def test_vision_drawn_in_whole_strides(exe, tmp_path):
    cfg = {"initial_population": "2000", "vision": "10,60", "look_stride": "10"}
    dump = run_gpu(exe, tmp_path, cfg, np.zeros((130, 130), dtype=int), steps=1, dump_at=0)
    assert dump.returncode == 0, dump.stderr
    assert {a["vision"] for a in dump.agents} == {10, 20, 30, 40, 50, 60}


def _east_stretch_run(exe, tmp_path, stride: int, seed: str, food=range(1, 11), vision=10,
                      spacing_x=SPACING_X) -> Counter:
    """Agents spaced spacing_x apart along x, each with capacity 4 on the sites east of it at the given distances
    and nothing else in view: how far each moved."""
    capacity = np.zeros((250, 100), dtype=int)
    agents = []
    for x in range(0, 250, spacing_x):
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


def test_one_look_per_stretch_at_uniform_offsets(exe, tmp_path):
    moved = Counter()
    for seed in ("1", "2"):
        (tmp_path / seed).mkdir()
        moved += _east_stretch_run(exe, tmp_path / seed, 10, seed)
    # Each agent saw exactly one of its 10 food sites, so it moved there; the offsets are uniform on 1..10.
    assert set(moved) == set(range(1, 11)), moved
    assert all(55 <= moved[d] <= 145 for d in range(1, 11)), moved


def test_second_stretch_is_looked_at_beyond_the_first(exe, tmp_path):
    # Vision 20 is two stretches; food only on sites 11-20 east. Every agent's one look there finds food, so every
    # agent moves 11-20 sites: this pins the stride * k term, which vision 10 (one stretch) never reaches.
    # 50 apart: at vision 20 the previous agent's food (21-40 sites west) is out of sight.
    moved = _east_stretch_run(exe, tmp_path, 10, "1", food=range(11, 21), vision=20, spacing_x=50)
    assert set(moved) <= set(range(11, 21)) and sum(moved.values()) == 250, moved
    assert len(moved) == 10, moved  # every offset in the second stretch occurs


def test_stride_one_looks_at_every_site(exe, tmp_path):
    # The control: seeing every site, every agent takes the nearest food, 1 site away.
    assert _east_stretch_run(exe, tmp_path, 1, "1") == Counter({1: 500})
