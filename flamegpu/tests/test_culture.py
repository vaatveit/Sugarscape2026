"""Culture K and friends in the turn (spec 2026-10-25-gpu-full-parity, section 4; Part A, Task 7).

Nobody moves (every capacity 0, vision 0). Exact comparisons with Python use equal tags, so tag flips change nothing
and the agents' order cannot matter; the transmission itself is tested by what it must give in either order.
"""

import math

import numpy as np
import pytest

from conftest import run_exe
from gpu import read_rows, run_gpu, write_cfg
from reference import python_metric_rows, run_python
from test_sex import _files

EMPTY = np.zeros((20, 20), dtype=int)
CULTURE = {"tag_length": "5", "culture": "true"}


def _agent(x, y, tags, **kw):
    return {"x": x, "y": y, "vision": 0, "metabolism": 1, "sugar": 50.0, "age": 30, "tags": tags, **kw}


def _by_uid(agents):
    return {a["uid"]: a for a in agents}


@pytest.mark.parametrize("seed", range(1))
def test_transmit_pair_converges(exe, tmp_path, seed):
    # A (tag 1) and B (tag 0) are each other's only neighbour: whoever goes first copies its tag to the other, who
    # copies it back. Either way they end equal, and over seeds both outcomes occur.
    outcomes = set()
    for k in range(20):
        (tmp_path / str(k)).mkdir()
        gpu = run_gpu(exe, tmp_path / str(k), {"tag_length": "1", "culture": "true", "seed": str(k)}, EMPTY,
                      [_agent(5, 5, "1"), _agent(6, 5, "0")], steps=1)
        assert gpu.returncode == 0, gpu.stderr
        tags = {a["tags"] for a in gpu.agents}
        assert len(tags) == 1, tags
        outcomes |= tags
    assert outcomes == {"0", "1"}


STAR = [_agent(5, 5, "00000"), _agent(6, 5, "00000"), _agent(4, 5, "00000"), _agent(5, 6, "00000"),
        _agent(5, 4, "00000")]


def test_friends_match_python(exe, tmp_path):
    # X at the centre meets its four neighbours; each neighbour meets X.
    gpu = run_gpu(exe, tmp_path, CULTURE, EMPTY, STAR, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(CULTURE, EMPTY, STAR, 1)
    assert {u: a["friends"] for u, a in _by_uid(gpu.agents).items()} == {u: a["friends"] for u, a in _by_uid(py.agents).items()}
    assert _by_uid(gpu.agents)[0]["friends"] == "1:0|2:0|3:0|4:0"


def test_dead_friend_dropped(exe, tmp_path):
    # The east neighbour starves in period 1: whether X met it first or not, X has no dead friend after period 2.
    agents = [dict(a, metabolism=500) if i == 1 else a for i, a in enumerate(STAR)]
    gpu = run_gpu(exe, tmp_path, CULTURE, EMPTY, agents, steps=2)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(CULTURE, EMPTY, agents, 2)
    assert {u: a["friends"] for u, a in _by_uid(gpu.agents).items()} == {u: a["friends"] for u, a in _by_uid(py.agents).items()}
    assert "1:" not in _by_uid(gpu.agents)[0]["friends"]


def test_friend_closeness_metrics(exe, tmp_path):
    # Friends given at t = 0 with different tags (distances as stored): both closeness columns match Python.
    agents = [_agent(2, 2, "00000", friends="1:2|2:4"), _agent(12, 2, "00011", friends="0:2"),
              _agent(2, 12, "01111", friends="0:4|1:3"), _agent(12, 12, "11111")]
    out = tmp_path / "metrics.csv"
    gpu = run_gpu(exe, tmp_path, CULTURE, EMPTY, agents, steps=1, extra_args=("--out", out))
    assert gpu.returncode == 0, gpu.stderr
    g = read_rows(out)[0]
    p = python_metric_rows(CULTURE, EMPTY, agents, 0)[0]
    for key in ("best_friend_closeness", "friend_closeness"):
        assert math.isclose(g[key], p[key], rel_tol=1e-12), (key, g[key], p[key])


III_8 = {"tag_length": "11", "culture": "true", "endowment": "25,50", "placement": "block", "block": "0,0,20,20",
         "initial_population": "400"}
III_15 = {"sex": "true", "max_age": "60,100", "endowment": "50,100", "initial_population": "100", "tag_length": "11",
          "culture": "true"}


@pytest.mark.parametrize("name, cfg", [("culture", III_8), ("culture_sex", III_15)])
def test_serial_equivalence(exe, tmp_path, name, cfg):
    waves = _files(exe, tmp_path / "w", cfg, 30)
    assert waves == _files(exe, tmp_path / "s", cfg, 30, "--serial-turns")
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg, steps="30"), "--check")
    assert result.returncode == 0, result.stderr
    # Friends are uids (a newborn's is fixed after the turns): every one names an agent made so far.
    ever = read_rows(tmp_path / "w" / "metrics.csv")[-1]["agents_ever"]
    header = waves["agents.csv"][0].split(",")
    col = header.index("friends")
    for line in waves["agents.csv"][1:]:
        friends = line.split(",")[col]
        assert all(int(f.split(":")[0]) < ever for f in friends.split("|") if f), friends
