"""Render agent positions over the capacity map at chosen times, one PNG per experiment."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
from dataclasses import replace
from pathlib import Path

from matplotlib.figure import Figure

from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

PLAN = {
    "II-1": [0, 5, 20, 50, 100],
    "II-4": [0, 10, 50, 150, 500],
    "II-6": [0, 20, 50, 100, 150, 200],
    "II-7": [0, 40, 75, 100, 125, 150],
    "II-8": [0, 45, 70, 99, 130, 200],
}

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for exp_id, times in PLAN.items():
    exp = EXPERIMENTS[exp_id]
    model = Model(replace(exp.config, seed=exp.config.seed))
    fig = Figure(figsize=(3 * len(times), 3.3))
    for i, t in enumerate(times):
        while model.t < t:
            model.step()
        ax = fig.add_subplot(1, len(times), i + 1)
        ax.imshow(model.landscape.capacity.T, origin="lower", cmap="YlOrBr", alpha=0.6)
        if exp.config.pollution:
            ax.imshow(model.landscape.pollution.T, origin="lower", cmap="Greys", alpha=0.35)
        ax.scatter([a.x for a in model.agents], [a.y for a in model.agents], s=4, c="k")
        ax.set_title(f"t={t}  n={len(model.agents)}", fontsize=9)
        ax.set_xticks([]); ax.set_yticks([])
    fig.suptitle(f"{exp_id} {exp.rules}")
    fig.tight_layout()
    fig.savefig(out / f"{exp_id}.png", dpi=70)
    print(exp_id, "done")
