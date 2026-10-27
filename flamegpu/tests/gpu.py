"""Helpers that drive the GPU program: run.cfg, map and init files, runs, and dumps."""

import csv
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from bridge.paths import SUGARSCAPE_ROOT
from conftest import run_exe

SUGAR_MAP = SUGARSCAPE_ROOT / "sugarscape" / "maps" / "sugar-map.txt"

# II-4's settings (50x50, G1, M) in run.cfg spelling; tests override what they need.
DEFAULT_CFG = {
    "width": "50",
    "height": "50",
    "map": str(SUGAR_MAP),
    "initial_population": "400",
    "placement": "random",
    "block": "0,0,20,20",
    "vision": "1,6",
    "metabolism": "1,4",
    "endowment": "25,50",
    "max_age": "",
    "founder_ages": "uniform",
    "replacement": "false",
    "growback_rate": "1",
    "seasons": "",
    "winter_growback": "fractional",
    "pollution": "",
    "pollution_start": "0",
    "pollution_stop": "",
    "diffusion_period": "",
    "diffusion_start": "0",
    # Chapter III (spec 2026-10-25-gpu-full-parity), at Python's Config defaults.
    "sex": "false",
    "fertility_start": "12,15",
    "female_fertility_end": "40,50",
    "male_fertility_end": "50,60",
    "inheritance": "false",
    "tag_length": "0",
    "culture": "false",
    "initial_blocks": "",
    "fertility_threshold": "1.0",
    "child_share": "0.5",
    "mate_contact": "vision",
    "child_gift": "endowment",
    "child_threshold": "endowment",
    "gift_rounding": "down",
    # Combat and same-tribe replacement (Part B).
    "combat_alpha": "",
    "replacement_same_tribe": "false",
    # Chapter IV (Part C).
    "spice": "false",
    "spice_metabolism": "1,5",
    "spice_endowment": "",
    "foresight": "",
    "cultural_preferences": "false",
    "trade": "false",
    "trade_rounding": "exact",
    "credit": "",
    "steps": "10",
    "seed": "0",
}


def write_cfg(directory: Path, **overrides: str) -> Path:
    """Write run.cfg with DEFAULT_CFG plus overrides (an override of None drops the key)."""
    cfg = {**DEFAULT_CFG, **overrides}
    path = Path(directory) / "run.cfg"
    path.write_text("".join(f"{k} = {v}\n" for k, v in cfg.items() if v is not None), encoding="utf-8")
    return path


def write_map(path: Path, rows: list[list[object]]) -> Path:
    """A map file in load_map's layout: one line per row, the first line northernmost."""
    Path(path).write_text("".join(" ".join(str(v) for v in row) + "\n" for row in rows), encoding="utf-8")
    return Path(path)


def parse_printed(stdout: str) -> dict[str, str]:
    """`key = value` lines from --print-config."""
    out = {}
    for line in stdout.splitlines():
        if " = " in line or line.endswith(" ="):
            key, _, value = line.partition("=")
            out[key.strip()] = value.strip()
    return out


# --- Running a scenario and reading the dumps (Task 3) -----------------------------------------

AGENT_FIELDS = ("x", "y", "vision", "metabolism", "sugar", "age", "max_age")


@dataclass
class Dump:
    agents: list[dict] = field(default_factory=list)  # x, y, vision, metabolism, sugar, age, max_age, moved, neighbors
    landscape: dict = field(default_factory=dict)  # (x, y) -> {capacity, sugar, pollution, occupied}
    csv: list[dict] | None = None
    returncode: int = 0
    stderr: str = ""


def capacity_rows(capacity: np.ndarray) -> list[list[int]]:
    """Map-file rows (first line northernmost) for a capacity array indexed [x, y]."""
    width, height = capacity.shape
    return [[int(capacity[x, y]) for x in range(width)] for y in range(height - 1, -1, -1)]


# --init's optional columns (spec 2026-10-25-gpu-full-parity, Task 2), written only when some agent sets them.
INIT_OPTIONAL = ("sex", "fertility_start", "fertility_end", "initial_sugar", "tags", "n_children", "parent_a", "parent_b",
                 "friends",
                 # Chapter IV (Part C). With spice on, an agent given no spice has 0 and starves at its first turn.
                 "spice", "initial_spice", "spice_metabolism", "foresight")
# Dump columns read as text, not numbers: tags is a 0/1 string, tag 0 first; friends is "uid:distance|...".
TEXT_COLUMNS = ("sex", "tags", "friends")


def write_init(path: Path, agents: list[dict]) -> Path:
    optional = [k for k in INIT_OPTIONAL if any(k in a for a in agents)]
    with Path(path).open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([*AGENT_FIELDS, *optional])
        for a in agents:
            writer.writerow([a["x"], a["y"], a["vision"], a["metabolism"], a["sugar"], a.get("age", 0),
                             "" if a.get("max_age") is None else a["max_age"],
                             *("" if a.get(k) is None else a[k] for k in optional)])
    return Path(path)


def _number(text: str):
    if text == "":
        return None
    if text in ("nan", "inf", "-inf"):
        return float(text)
    return int(text) if text.lstrip("-").isdigit() else float(text)


def read_rows(path: Path) -> list[dict]:
    with Path(path).open(newline="") as f:
        return [{k: v if k in TEXT_COLUMNS else _number(v) for k, v in row.items()} for row in csv.DictReader(f)]


def run_gpu(exe: Path, tmp: Path, cfg: dict | None = None, capacity: np.ndarray | None = None,
            agents: list[dict] | None = None, steps: int = 1, dump_at: int | None = None,
            extra_args: tuple = ()) -> Dump:
    """Run one scenario: cfg overrides DEFAULT_CFG; capacity (indexed [x, y]) replaces the map; agents replace
    the random initial population. Dumps are taken at `dump_at` (default: after the last step)."""
    tmp = Path(tmp)
    cfg = dict(cfg or {})
    cfg["steps"] = str(steps)
    if capacity is not None:
        cfg["map"] = str(write_map(tmp / "map.txt", capacity_rows(capacity)))
        cfg["width"], cfg["height"] = str(capacity.shape[0]), str(capacity.shape[1])
    if agents is not None:
        cfg.setdefault("initial_population", str(len(agents)))
    args = ["--config", write_cfg(tmp, **cfg)]
    if agents is not None:
        args += ["--init", write_init(tmp / "init.csv", agents)]
    t = steps if dump_at is None else dump_at
    args += ["--dump-agents", tmp / "agents.csv", "--dump-landscape", tmp / "landscape.csv", "--dump-at", str(t)]
    result = run_exe(exe, *args, *extra_args)
    dump = Dump(returncode=result.returncode, stderr=result.stderr)
    if result.returncode != 0:
        return dump
    dump.agents = read_rows(tmp / "agents.csv")
    dump.landscape = {(r["x"], r["y"]): r for r in read_rows(tmp / "landscape.csv")}
    return dump


def period_orders(exe: Path, tmp: Path, cfg: dict | None, capacity: np.ndarray | None, agents: list[dict] | None,
                  steps: int) -> list[list[int]]:
    """Each period's uids in the GPU's turn order (--dump-order), for stepping Python in the same order
    (reference.run_python_in_order) where the order matters."""
    tmp = Path(tmp)
    tmp.mkdir(parents=True, exist_ok=True)
    order_file = tmp / "order.csv"
    dump = run_gpu(exe, tmp, cfg, capacity, agents, steps, extra_args=("--dump-order", order_file))
    assert dump.returncode == 0, dump.stderr
    orders = [[] for _ in range(steps)]
    for row in read_rows(order_file):
        orders[row["t"] - 1].append(row["uid"])
    return orders


def compare_dumps(gpu: Dump, py: Dump, pollution: bool = False) -> list[str]:
    """Differences between two dumps of the same scenario; empty when they agree."""
    problems = []
    key = lambda a: (a["x"], a["y"], a["vision"], a["metabolism"], a["age"])  # noqa: E731
    g = {key(a): a for a in gpu.agents}
    p = {key(a): a for a in py.agents}
    if set(g) != set(p):
        problems.append(f"agents differ: gpu-only {sorted(set(g) - set(p))}, python-only {sorted(set(p) - set(g))}")
    for k in set(g) & set(p):
        for good in ("sugar", "spice"):  # spice wherever both dumps carry it (Part C)
            if good not in g[k] or good not in p[k]:
                continue
            if not math.isclose(g[k][good], p[k][good], abs_tol=1e-5):
                problems.append(f"agent {k}: {good} gpu {g[k][good]} python {p[k][good]}")
    for site, pc in py.landscape.items():
        gc = gpu.landscape[site]
        for good in ("sugar", "spice"):
            if good not in gc or good not in pc:
                continue
            if not math.isclose(gc[good], pc[good], abs_tol=1e-5):
                problems.append(f"site {site}: {good} gpu {gc[good]} python {pc[good]}")
        if gc["occupied"] != pc["occupied"]:
            problems.append(f"site {site}: occupied gpu {gc['occupied']} python {pc['occupied']}")
        if pollution and not math.isclose(gc["pollution"], pc["pollution"], rel_tol=1e-4, abs_tol=1e-5):
            problems.append(f"site {site}: pollution gpu {gc['pollution']} python {pc['pollution']}")
    return problems
