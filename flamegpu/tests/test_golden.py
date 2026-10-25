"""Golden runs: today's 50x50 output, byte for byte, so refactors can prove they changed none of it.

The files in data/golden/ were written by make_golden.py with the program as it was before the xl work. Never
regenerate them to make a test pass: a difference means behaviour changed.

One deliberate regeneration, approved by the user: on 2026-10-25 replacement moved to the device (spec
2026-10-25-gpu-replacement-metrics), which changed its random stream by design. Only the files replacement reaches
were rewritten: gini_t0/metrics.csv (from t = 1) and gini_t30/*.

A second deliberate regeneration of every case, approved by the user with the design: on 2026-10-25 movement and
neighbour counts moved to Python's one-agent-at-a-time order (spec 2026-10-25-gpu-sequential-semantics), which changed
every run, and the agent dumps gained id, priority, dir_order and look_seed. gini_t0's landscape (t = 0, before any
move) is unchanged.
"""

from pathlib import Path

import pytest

from conftest import run_exe
from gpu import write_cfg
from test_parity import GINI_CFG

GOLDEN = Path(__file__).resolve().parent / "data" / "golden"
FILES = ("metrics.csv", "agents.csv", "landscape.csv")

# name -> (run.cfg overrides of DEFAULT_CFG, steps, dump_at); all 50x50 on sugar-map.txt, seed 0.
GOLDEN_CASES: dict[str, tuple[dict, int, int]] = {
    "gini_t0": (GINI_CFG, 30, 0),
    "gini_t30": (GINI_CFG, 30, 30),
    "diffusion": ({"pollution": "1.0,1.0", "diffusion_period": "2", "diffusion_start": "1"}, 15, 15),
    "block_seasons": ({"placement": "block", "seasons": "4,3"}, 20, 20),
}


def run_case(exe: Path, tmp: Path, name: str) -> dict[str, bytes]:
    """Run one golden case and return the bytes of its metrics CSV and its agent and landscape dumps."""
    cfg, steps, dump_at = GOLDEN_CASES[name]
    tmp = Path(tmp)
    result = run_exe(exe, "--config", write_cfg(tmp, **cfg, steps=str(steps)), "--out", tmp / "metrics.csv",
                     "--dump-agents", tmp / "agents.csv", "--dump-landscape", tmp / "landscape.csv",
                     "--dump-at", str(dump_at))
    assert result.returncode == 0, result.stderr
    return {f: (tmp / f).read_bytes() for f in FILES}


def comparable(f: str, data: bytes) -> bytes:
    """The bytes compared: agents.csv without its id column. FLAME GPU numbers agents born on the device (replacement
    newcomers) in thread order, so their ids vary between runs; the founders' ids and every other byte do not."""
    if f != "agents.csv":
        return data
    lines = data.decode().splitlines()
    drop = lines[0].split(",").index("id")
    return "\n".join(",".join(v for i, v in enumerate(line.split(",")) if i != drop) for line in lines).encode()


@pytest.mark.parametrize("name", GOLDEN_CASES)
def test_matches_golden(exe, tmp_path, name):
    got = run_case(exe, tmp_path, name)
    for f in FILES:
        assert comparable(f, got[f]) == comparable(f, (GOLDEN / name / f).read_bytes()), \
            f"{name}/{f} differs from the golden run"
