"""Chapter V snapshots: sick red, well blue (Animations V-1, V-2); infection edges this period (V-3)."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys
from pathlib import Path

from matplotlib.figure import Figure

from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
for exp_id in ("V-1", "V-2"):
    m = Model(EXPERIMENTS[exp_id].config)
    fig = Figure(figsize=(18, 3.3))
    for i, t in enumerate((0, 1, 3, 10, 50, 500)):
        while m.t < t:
            m.step()
        ax = fig.add_subplot(1, 6, i + 1)
        ax.imshow(m.landscape.capacity.T, origin="lower", cmap="Greys", alpha=0.3)
        for s_, t_ in m.infection_log:
            ax.plot([s_.x, t_.x], [s_.y, t_.y], color="0.4", lw=0.6)
        ax.scatter([a.x for a in m.agents], [a.y for a in m.agents], s=5,
                   c=["tab:red" if a.diseases else "tab:blue" for a in m.agents])
        sick = sum(1 for a in m.agents if a.diseases)
        ax.set_title(f"t={t} n={len(m.agents)} sick={sick} new={len(m.infection_log)}", fontsize=8)
        ax.set_xticks([]); ax.set_yticks([])
    fig.tight_layout(); fig.savefig(out / f"{exp_id}.png", dpi=70)
print("done")
