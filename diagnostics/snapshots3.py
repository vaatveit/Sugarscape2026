"""Chapter III snapshot panels: agents over the capacity map, colored like the book's animations."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import sys
from pathlib import Path

from matplotlib.figure import Figure

from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

PLAN = {
    "III-1": ([0, 50, 150, 300, 600, 900], "vision"),
    "III-8": ([0, 200, 500, 1000, 2000, 3000], "tribe"),
    "III-9": ([0, 20, 50, 100, 300, 1000], "tribe"),
    "III-11": ([0, 50, 150, 300, 600, 1000], "tribe"),
    "III-12": ([0, 5, 10, 20, 40, 100], "tribe"),
    "III-15": ([0, 50, 150, 300, 600, 1000], "tribe"),
}


def colour(agent, mode):
    if mode == "vision":
        return "tab:red" if agent.vision >= 4 else "tab:blue"
    return "tab:blue" if agent.tribe == "blue" else "tab:red"


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
only = sys.argv[2:] or list(PLAN)
for exp_id in only:
    times, mode = PLAN[exp_id]
    exp = EXPERIMENTS[exp_id]
    model = Model(exp.config)
    fig = Figure(figsize=(3 * len(times), 3.3))
    for i, t in enumerate(times):
        while model.t < t:
            model.step()
        ax = fig.add_subplot(1, len(times), i + 1)
        ax.imshow(model.landscape.capacity.T, origin="lower", cmap="Greys", alpha=0.35)
        ax.scatter([a.x for a in model.agents], [a.y for a in model.agents], s=4,
                   c=[colour(a, mode) for a in model.agents])
        ax.set_title(f"t={t}  n={len(model.agents)}", fontsize=9)
        ax.set_xticks([])
        ax.set_yticks([])
    fig.suptitle(f"{exp_id} {exp.rules} (colour: {mode})")
    fig.tight_layout()
    fig.savefig(out / f"{exp_id}.png", dpi=70)
    print(exp_id, "done", flush=True)
