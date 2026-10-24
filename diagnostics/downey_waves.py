"""Animation II-6's waves under Think Complexity's settings (Downey 2018, sec. 9.7; code in the book's repository,
soln/chap09.ipynb, read 2026-10-23). Downey shows diagonal waves from a block start, but with settings of his own:
300 agents in a 20x20 SW block, vision 1-16 (the text's II-6 uses 1-10), the agent's own site never a candidate
(it stays only when every visible site is occupied), metabolism U(1,4) and endowment U(5,25) as real numbers, and a
generated map (capacity by distance to peaks at (15,15) and (35,35), bins 21/16/11/6). He shows t=6 and t=12 only.

Each setting adds Downey's departures to II-6 as registered, one at a time and then together (and Downey's map
under the registered agents), and reports the NE
share (agents with x, y >= 25; II-6's target reads it at t=200, band 0.15-1) at several times, 5 seeds.
"kymo" draws, for seed 0 of each setting, the agents' density along the diagonal (x + y) against time: a wave is a
stripe climbing to larger x + y, with an empty stripe behind it (output/downey_waves.png).
Diagnostic only: nothing here changes the model.

Usage: downey_waves.py [jobs]
       downey_waves.py kymo [jobs]
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from matplotlib.figure import Figure

from _paths import ROOT
from experiments.registry import EXPERIMENTS
from probe_falls import ORIGINAL_MOVE, must_move
from sugarscape.model import Model
from sugarscape.rules import movement

SETTINGS = {
    "II-6 as registered": set(),
    "vision 1-16": {"vision"},
    "must move": {"mustmove"},
    "vision 1-16 + must move": {"vision", "mustmove"},
    "Downey's agents (all but the map)": {"vision", "mustmove", "agents"},
    "Downey's agents and map": {"vision", "mustmove", "agents", "map"},
    "Downey's map only": {"map"},
    "Downey's map + vision 1-16": {"map", "vision"},
}
TIMES = (6, 12, 25, 50, 100, 200, 300)
SEEDS = 5
KYMO_STEPS = 150


def downey_capacity(n=50):
    """Think Complexity's make_capacity: np.digitize of the distance to the nearer peak, bins [21, 16, 11, 6]."""
    x, y = np.indices((n, n))
    dist = np.minimum(np.hypot(x - 15, y - 15), np.hypot(x - 35, y - 35))
    return np.digitize(dist, [21, 16, 11, 6])


def build(name, k):
    parts = SETTINGS[name]
    movement.move = must_move if "mustmove" in parts else ORIGINAL_MOVE  # workers are reused; reset every run
    exp = EXPERIMENTS["II-6"]
    cfg = replace(exp.config, seed=exp.config.seed + k)
    if "vision" in parts:
        cfg = replace(cfg, vision=(1, 16))
    if "agents" in parts:
        cfg = replace(cfg, initial_population=300)
    m = Model(cfg)
    if "agents" in parts:
        for a in m.agents:
            a.metabolism = float(m.rng.uniform(1, 4))
            a.sugar = a.initial_sugar = float(m.rng.uniform(5, 25))
    if "map" in parts:
        m.landscape.capacity[:] = downey_capacity()
        m.landscape.sugar[:] = m.landscape.capacity
    return m


def run(args):
    name, k = args
    m = build(name, k)
    ne = {}
    for t in range(max(TIMES) + 1):
        if t in TIMES:
            ne[t] = np.mean([a.x >= 25 and a.y >= 25 for a in m.agents]) if m.agents else float("nan")
        m.step()
    return name, ne


def kymo(name):
    m = build(name, 0)
    rows = []
    for _ in range(KYMO_STEPS + 1):
        rows.append(np.bincount([a.x + a.y for a in m.agents], minlength=99))
        m.step()
    return name, np.array(rows)


def draw(panels):
    cols = (len(panels) + 1) // 2
    fig = Figure(figsize=(4 * cols, 7))
    axes = fig.subplots(2, cols, sharex=True, sharey=True).ravel()
    for ax, (name, rows) in zip(axes, panels):
        ax.imshow(rows.T, origin="lower", aspect="auto", cmap="Greys", vmax=np.percentile(rows, 99))
        ax.set_title(name, fontsize=9)
    for ax in axes[cols:]:
        ax.set_xlabel("t")
    for ax in axes[::cols]:
        ax.set_ylabel("x + y")
    fig.suptitle("II-6, seed 0: agents per diagonal (x + y) over time; a wave is a stripe climbing to the NE")
    fig.tight_layout()
    fig.savefig(ROOT / "diagnostics" / "output" / "downey_waves.png", dpi=80)


if __name__ == "__main__":
    if sys.argv[1:2] == ["kymo"]:
        with ProcessPoolExecutor(int(sys.argv[2]) if len(sys.argv) > 2 else 6) as pool:
            draw(list(pool.map(kymo, SETTINGS)))
        sys.exit()
    jobs = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    with ProcessPoolExecutor(jobs) as pool:
        res = list(pool.map(run, [(s, k) for s in SETTINGS for k in range(SEEDS)]))
    print(f"II-6 NE share (agents with x, y >= 25), mean of {SEEDS} seeds [min-max]; target at t=200: 0.15-1")
    print("| Setting | " + " | ".join(f"t={t}" for t in TIMES) + " |")
    print("|---|" + "---|" * len(TIMES))
    for s in SETTINGS:
        vals = [ne for name, ne in res if name == s]
        cells = [f"{np.mean([v[t] for v in vals]):.3f} [{min(v[t] for v in vals):.2f}-{max(v[t] for v in vals):.2f}]"
                 for t in TIMES]
        print(f"| {s} | " + " | ".join(cells) + " |")
