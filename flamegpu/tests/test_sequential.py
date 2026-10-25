"""Python's one-agent-at-a-time order on the GPU (spec 2026-10-25-gpu-sequential-semantics): the period's order,
deferred-acceptance movement, and in-order neighbour counts, checked against replays of the GPU's own draws."""

import numpy as np
import pytest

from gpu import run_gpu

# 400 agents packed in a 20x20 block: wave fronts with many contested sites (II-6's start, at 50x50).
BLOCK = {"placement": "block", "block": "0,0,20,20", "initial_population": "400", "vision": "1,6"}
# No deaths before t = 6 (immortal, endowment >= 25 against metabolism <= 4), so every agent of period t is in both
# dumps and can be replayed; no pollution, so every score is a whole sugar amount in float32 and float64 alike.
DEATHLESS = {**BLOCK, "endowment": "25,50", "max_age": ""}

MOVE_DX, MOVE_DY = (1, -1, 0, 0), (0, 0, 1, -1)  # VON_NEUMANN: east, west, north, south
M32 = 0xFFFFFFFF


def _mix32(h):  # movement.cuh's mix32 (lowbias32), on 32-bit unsigned arithmetic
    h ^= h >> 16
    h = (h * 0x7FEB352D) & M32
    h ^= h >> 15
    h = (h * 0x846CA68B) & M32
    h ^= h >> 16
    return h


def _look_distance(seed, d, k, stride):  # movement.cuh's look_distance
    h = _mix32(_mix32(seed ^ ((d * 0x9E3779B9) & M32)) ^ (((k + 1) * 0x85EBCA6B) & M32))
    return stride * k + 1 + h % stride


def _key(a):
    return a["priority"] << 32 | a["id"]


def _dumps(exe, tmp_path, cfg, t):
    """The dumps at t - 1 and t of one run (two runs with the same seed and steps, so the same draws)."""
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    prev = run_gpu(exe, tmp_path / "a", cfg, steps=t, dump_at=t - 1)
    cur = run_gpu(exe, tmp_path / "b", cfg, steps=t, dump_at=t)
    assert prev.returncode == 0, prev.stderr
    assert cur.returncode == 0, cur.stderr
    return prev, cur


def serial_dictatorship(prev, cur, width, height, stride=1):
    """Python's rule M one agent at a time, in the GPU's order of period t, over the sites free at its start: each
    agent's final site by id. The period's order, directions and looks come from the t dump; start sites, visions
    and the landscape from the t - 1 dump."""
    start = {a["id"]: a for a in prev.agents}
    occupied = {(a["x"], a["y"]) for a in prev.agents}
    sugar = {site: row["sugar"] for site, row in prev.landscape.items()}
    taken, final = set(), {}
    for a in sorted(cur.agents, key=_key, reverse=True):
        s = start[a["id"]]
        x, y, vision = s["x"], s["y"], s["vision"]
        best = (sugar[(x, y)], 0, (x, y))
        for i in range(4):
            d = (a["dir_order"] >> (2 * i)) & 3
            dists = (range(1, vision + 1) if stride == 1
                     else [_look_distance(a["look_seed"], d, k, stride) for k in range(vision // stride)])
            for dist in dists:
                site = ((x + MOVE_DX[d] * dist) % width, (y + MOVE_DY[d] * dist) % height)
                if site in occupied or site in taken:
                    continue
                score = sugar[site]
                if score > best[0] or (score == best[0] and dist < best[1]):
                    best = (score, dist, site)
        if best[2] != (x, y):
            taken.add(best[2])
        final[a["id"]] = best[2]
    return final


def in_order_neighbours(prev, cur, width, height):
    """Python's neighbour count at each agent's turn (no deaths): an earlier agent counts at its final site, a later
    agent at its start site, since it has not moved yet."""
    start = {a["id"]: (a["x"], a["y"]) for a in prev.agents}
    counts = {}
    for p in cur.agents:
        k = _key(p)
        seen = {(a["x"], a["y"]) for a in cur.agents if _key(a) > k} | {start[a["id"]] for a in cur.agents if _key(a) < k}
        counts[p["id"]] = sum(((p["x"] + dx) % width, (p["y"] + dy) % height) in seen for dx, dy in zip(MOVE_DX, MOVE_DY))
    return counts


def test_period_order_in_dump(exe, tmp_path):
    dump = run_gpu(exe, tmp_path, BLOCK, steps=3)
    assert dump.returncode == 0, dump.stderr
    orders = [[(a["dir_order"] >> (2 * i)) & 3 for i in range(4)] for a in dump.agents]
    assert all(sorted(o) == [0, 1, 2, 3] for o in orders)
    assert len({tuple(o) for o in orders}) == 24  # 400 draws reach every permutation
    assert len({a["priority"] for a in dump.agents}) == 400  # 32 bits: no ties at 400
    assert max(a["priority"] for a in dump.agents) > 2 ** 20  # not the old 20 bits
    assert len({a["id"] for a in dump.agents}) == 400
    assert all(a["look_seed"] == 0 for a in dump.agents)  # drawn only above stride 1


@pytest.mark.parametrize("t", [2, 3, 4, 5, 6])
def test_movement_is_serial_dictatorship(exe, tmp_path, t):
    prev, cur = _dumps(exe, tmp_path, DEATHLESS, t)
    assert len(cur.agents) == len(prev.agents) == 400
    got = {a["id"]: (a["x"], a["y"]) for a in cur.agents}
    assert serial_dictatorship(prev, cur, 50, 50) == got


@pytest.mark.parametrize("t", [2, 3, 4, 5])
def test_movement_is_serial_dictatorship_with_stride(exe, tmp_path, t):
    # Look stride 5: one hashed look per stretch, the same in every round (xl design 2a), replayed from look_seed.
    prev, cur = _dumps(exe, tmp_path, {**DEATHLESS, "look_stride": "5", "vision": "5,20"}, t)
    assert len(cur.agents) == len(prev.agents) == 400
    got = {a["id"]: (a["x"], a["y"]) for a in cur.agents}
    assert serial_dictatorship(prev, cur, 50, 50, stride=5) == got


@pytest.mark.parametrize("t", [2, 3, 4, 5, 6])
def test_neighbours_in_order(exe, tmp_path, t):
    # Consecutive periods: no per-site order key from one period may leak into the next, when every priority is new.
    prev, cur = _dumps(exe, tmp_path, DEATHLESS, t)
    assert in_order_neighbours(prev, cur, 50, 50) == {a["id"]: a["neighbors"] for a in cur.agents}


FLAT = np.full((10, 10), 3, dtype=int)  # equal sites: nobody moves (an equal site never beats one's own)


def _pair(a_sugar, a_metabolism, a_max_age):
    return [{"x": 5, "y": 5, "vision": 1, "metabolism": a_metabolism, "sugar": a_sugar, "age": 0, "max_age": a_max_age},
            {"x": 6, "y": 5, "vision": 1, "metabolism": 1, "sugar": 10.0, "age": 0, "max_age": None}]


def test_old_age_neighbour_still_counted(exe, tmp_path):
    # Python removes old-age deaths at the end of the period, so B counts A whatever the order: 10 seeds, so both
    # orders occur (dropping A at its turn would fail whenever A comes first).
    for seed in range(10):
        d = tmp_path / str(seed)
        d.mkdir()
        dump = run_gpu(exe, d, {"vision": "1,1", "seed": str(seed)}, FLAT, _pair(10.0, 1, 1), steps=1)
        assert dump.returncode == 0, dump.stderr
        assert [(a["x"], a["y"], a["neighbors"]) for a in dump.agents] == [(6, 5, 1)], seed


def test_starved_neighbour_counted_half_the_time(exe, tmp_path):
    # A starves at its own turn (0.5 + 3 harvested - 4 < 0): B counts it only when A comes later in the order.
    counted = 0
    for seed in range(60):
        d = tmp_path / str(seed)
        d.mkdir()
        dump = run_gpu(exe, d, {"vision": "1,1", "seed": str(seed)}, FLAT, _pair(0.5, 4, None), steps=1)
        assert dump.returncode == 0, dump.stderr
        (b,) = dump.agents
        counted += b["neighbors"]
    assert 0.3 <= counted / 60 <= 0.7, counted
