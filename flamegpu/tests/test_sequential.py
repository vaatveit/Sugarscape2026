"""Python's one-agent-at-a-time order on the GPU (spec 2026-10-25-gpu-sequential-semantics): the period's order,
deferred-acceptance movement, and in-order neighbour counts, checked against replays of the GPU's own draws."""

from gpu import run_gpu

# 400 agents packed in a 20x20 block: wave fronts with many contested sites (II-6's start, at 50x50).
BLOCK = {"placement": "block", "block": "0,0,20,20", "initial_population": "400", "vision": "1,6"}


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
