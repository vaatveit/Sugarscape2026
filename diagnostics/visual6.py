"""Chapter VI visual check: VI-1 boards, VI-2/VI-3 curves, Schelling boards, Ring World space-time."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
from dataclasses import replace
from pathlib import Path

import numpy as np
from matplotlib.figure import Figure

from experiments.registry import EXPERIMENTS
from experiments.run import load_results
from sugarscape.model import Model
from sugarscape.variants.ringworld import RingModel
from sugarscape.variants.schelling import SchellingModel

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)


def vi1():
    m = Model(EXPERIMENTS["VI-1"].config)
    fig = Figure(figsize=(16, 4.4))
    shots = (0, 50, 120, 500)
    for k, t_stop in enumerate(shots):
        while m.t < t_stop:
            m.step()
        ax = fig.add_subplot(1, 4, k + 1)
        ax.imshow(m.landscape.capacity.T, origin="lower", cmap="Greys", alpha=0.35)
        sick = [a for a in m.agents if a.diseases]
        well = [a for a in m.agents if not a.diseases]
        ax.scatter([a.x for a in well], [a.y for a in well], s=6, c="tab:blue")
        ax.scatter([a.x for a in sick], [a.y for a in sick], s=6, c="tab:red")
        ax.set_title(f"t={m.t}  n={len(m.agents)}  sick={len(sick)}  loans={len(m.loans)}")
    fig.tight_layout()
    fig.savefig(OUT / "vi1.png", dpi=80)


def indecomposability():
    fig = Figure(figsize=(12, 4))
    for k, exp_id in enumerate(("VI-2", "VI-3")):
        ax = fig.add_subplot(1, 2, k + 1)
        for s in load_results(exp_id):
            ax.plot([r["t"] for r in s], [r["population"] for r in s], lw=0.8)
        ax.set_ylim(0, 1500)
        ax.set_title(exp_id)
    fig.tight_layout()
    fig.savefig(OUT / "vi2_vi3.png", dpi=80)


def schelling():
    fig = Figure(figsize=(16, 8))
    for k, exp_id in enumerate(("VI-4", "VI-5", "VI-6", "VI-7")):
        m = SchellingModel(EXPERIMENTS[exp_id].config)
        for row, t_stop in enumerate((0, 500)):
            m.run(t_stop - m.t)
            board = np.full((50, 50), 0.5)
            for a in m.agents:
                board[a.x, a.y] = 1.0 if a.color == "red" else 0.0
            ax = fig.add_subplot(2, 4, row * 4 + k + 1)
            ax.imshow(board.T, origin="lower", cmap="coolwarm", vmin=0, vmax=1)
            ax.set_title(f"{exp_id} t={m.t}")
            ax.set_xticks([])
            ax.set_yticks([])
    fig.tight_layout()
    fig.savefig(OUT / "schelling.png", dpi=80)


def ring():
    fig = Figure(figsize=(12, 7))
    for k, exp_id in enumerate(("VI-8", "VI-9")):
        m = RingModel(replace(EXPERIMENTS[exp_id].config, seed=0))
        img = np.zeros((80, m.config.sites))
        for t in range(80):
            for a in m.agents:
                img[t, a.position] = 1
            m.step()
        ax = fig.add_subplot(1, 2, k + 1)
        ax.imshow(img, origin="lower", aspect="auto", cmap="Greys", interpolation="nearest")
        ax.set_title(f"{exp_id}: ring position (x) vs t (y)")
    fig.tight_layout()
    fig.savefig(OUT / "ring.png", dpi=80)


if __name__ == "__main__":
    for job in sys.argv[2:]:
        globals()[job]()
        print(job, "done", flush=True)
