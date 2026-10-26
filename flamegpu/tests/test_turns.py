"""The device store and the ordered turns (spec 2026-10-25-gpu-full-parity, section 2; Part A, Task 4).

With Chapter II's rules the turns must reproduce today's path byte for byte, and waves must equal serial mode.
"""

import json
import math

import pytest

from conftest import run_exe
from gpu import read_rows, write_cfg, write_map
from test_parity import GINI_CFG

FILES = ("metrics.csv", "agents.csv", "landscape.csv")
II_4 = {}
II_6 = {"placement": "block", "block": "0,0,20,20", "vision": "1,10"}
II_7 = {"seasons": "4,3"}
II_8 = {"pollution": "1.0,1.0", "pollution_start": "5", "diffusion_period": "1", "diffusion_start": "10"}


def _files(exe, tmp, cfg, steps, dump_at, *extra) -> dict[str, bytes]:
    tmp.mkdir(parents=True, exist_ok=True)
    result = run_exe(exe, "--config", write_cfg(tmp, **cfg, steps=str(steps)), "--out", tmp / "metrics.csv",
                     "--dump-agents", tmp / "agents.csv", "--dump-landscape", tmp / "landscape.csv",
                     "--dump-at", str(dump_at), *extra)
    assert result.returncode == 0, result.stderr
    return {f: (tmp / f).read_bytes() for f in FILES}


@pytest.mark.parametrize("name, cfg", [("II-4", II_4), ("II-8", II_8), ("II-7", II_7)])
@pytest.mark.parametrize("dump_at", [3, 20])
def test_turns_path_equals_fast_path(exe, tmp_path, name, cfg, dump_at):
    fast = _files(exe, tmp_path / "fast", cfg, 20, dump_at)
    turns = _files(exe, tmp_path / "turns", cfg, 20, dump_at, "--force-turns")
    for f in FILES:
        assert turns[f] == fast[f], f"{name}: {f} differs between the turns and today's path"


def test_serial_equivalence_chapter2(exe, tmp_path):
    waves = _files(exe, tmp_path / "waves", II_6, 10, 10, "--force-turns")
    serial = _files(exe, tmp_path / "serial", II_6, 10, 10, "--force-turns", "--serial-turns")
    assert waves == serial


def _timing(exe, tmp_path, cfg, *extra) -> dict:
    timing = tmp_path / "timing.json"
    result = run_exe(exe, "--config", write_cfg(tmp_path, **{"steps": "5", **cfg}), "--timing", timing, *extra)
    assert result.returncode == 0, result.stderr
    return json.loads(timing.read_text())


def test_waves_reported(exe, tmp_path):
    assert _timing(exe, tmp_path, {}, "--force-turns")["waves_mean"] >= 1
    assert _timing(exe, tmp_path, {})["waves_mean"] == 0


def test_dependency_chain(exe, tmp_path):
    # A row of 12 agents, each next to the next: every turn waits for its neighbours earlier in the order.
    write_map(tmp_path / "map.txt", [[1] * 12, [4] * 12, [1] * 12])
    init = tmp_path / "init.csv"
    init.write_text("x,y,vision,metabolism,sugar,age,max_age\n" +
                    "".join(f"{x},1,1,1,10,0,\n" for x in range(12)))
    cfg = {"width": "12", "height": "3", "map": str(tmp_path / "map.txt"), "vision": "1,1",
           "initial_population": "12"}
    a = _files(exe, tmp_path / "a", cfg, 4, 4, "--init", init, "--force-turns")
    b = _files(exe, tmp_path / "b", cfg, 4, 4, "--init", init, "--force-turns", "--serial-turns")
    assert a == b
    assert _timing(exe, tmp_path / "a", cfg, "--force-turns", "--init", init)["waves_mean"] > 1


def test_turns_extinction(exe, tmp_path):
    out = tmp_path / "metrics.csv"
    result = run_exe(exe, "--config", write_cfg(tmp_path, metabolism="500,500", steps="5"), "--out", out,
                     "--force-turns")
    assert result.returncode == 0, result.stderr
    rows = read_rows(out)
    assert [r["t"] for r in rows] == list(range(6))
    for r in rows[1:]:
        assert r["population"] == 0 and math.isnan(r["mean_sugar"]) and r["mean_children"] == 0.0


def test_turns_replacement_counts(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **GINI_CFG, steps="30"), "--force-turns", "--check")
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("extra", [(), ("--force-turns",)])
def test_newcomer_uids_deterministic(exe, tmp_path, extra):
    # Newcomers' uids follow their deaths' order (starved first, in the period's order, then old age by uid), so they
    # repeat run to run; FLAME GPU's own ids for them do not (test_golden).
    a = _files(exe, tmp_path / "a", GINI_CFG, 30, 30, *extra)["agents.csv"]
    b = _files(exe, tmp_path / "b", GINI_CFG, 30, 30, *extra)["agents.csv"]
    uid = lambda data: [line.split(",")[a_header.index("uid")] for line in data.decode().splitlines()[1:]]  # noqa: E731
    a_header = a.decode().splitlines()[0].split(",")
    assert uid(a) == uid(b)
    assert len(set(uid(a))) == len(uid(a)) and max(int(u) for u in uid(a)) >= 250
