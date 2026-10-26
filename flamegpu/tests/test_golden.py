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

A third regeneration, columns added only, approved with the design (spec 2026-10-25-gpu-full-parity, Constraints):
on 2026-10-25 metrics.csv gained Python's other 33 metric columns and agents.csv the Chapter III variables. Every
column of the files before it was checked byte-identical in the files after it (Part A ledger, Task 3), and the
comparison is now by column name, so a later run may add columns but never change one the goldens hold.
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


# Never compared: FLAME GPU numbers agents born on the device (replacement newcomers) in thread order, so their ids
# vary between runs; the founders' ids and every other byte do not. Newcomers' uids are also handed out in thread
# order until the turns give them Python's creation order (Part A, Task 4).
UNSTABLE = ("id", "uid")


def comparable(f: str, data: bytes, columns: list[str]) -> bytes:
    """The bytes compared: the named columns, in that order (the golden file's columns, so a run may add new ones)."""
    lines = data.decode().splitlines()
    header = lines[0].split(",")
    keep = [header.index(c) for c in columns if c not in UNSTABLE]
    return "\n".join(",".join(line.split(",")[i] for i in keep) for line in lines).encode()


@pytest.mark.parametrize("name", GOLDEN_CASES)
def test_matches_golden(exe, tmp_path, name):
    got = run_case(exe, tmp_path, name)
    for f in FILES:
        golden = (GOLDEN / name / f).read_bytes()
        columns = golden.decode().splitlines()[0].split(",")
        assert all(c in got[f].decode().splitlines()[0].split(",") for c in columns), f"{name}/{f} lost a column"
        assert comparable(f, got[f], columns) == comparable(f, golden, columns), f"{name}/{f} differs from the golden run"
