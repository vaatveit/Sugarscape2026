"""Chapter IV snapshots: agents on the sugar+spice map (IV-1-like), trade edges (IV-4), credit (IV-5)."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys
from pathlib import Path

from matplotlib.figure import Figure

from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)

m = Model(EXPERIMENTS["IV-3"].config)
fig = Figure(figsize=(18, 3.3))
for i, t in enumerate((0, 1, 10, 50, 200, 500)):
    while m.t < t:
        m.step()
    ax = fig.add_subplot(1, 6, i + 1)
    ax.imshow((m.landscape.capacity + m.landscape.spice_capacity).T, origin="lower", cmap="Greys", alpha=0.35)
    for d in m.trade_log:
        ax.plot([d.a.x, d.b.x], [d.a.y, d.b.y], color="tab:green", lw=0.8)
    ax.scatter([a.x for a in m.agents], [a.y for a in m.agents], s=4, c="k")
    ax.set_title(f"t={t} n={len(m.agents)} trades={len(m.trade_log)}", fontsize=8)
    ax.set_xticks([]); ax.set_yticks([])
fig.tight_layout(); fig.savefig(out / "IV-3-trade-network.png", dpi=70)

m = Model(EXPERIMENTS["IV-A5"].config)
fig = Figure(figsize=(15, 3.3))
for i, t in enumerate((50, 100, 200, 300, 500)):
    while m.t < t:
        m.step()
    lenders = {id(l.lender) for l in m.loans}; borrowers = {id(l.borrower) for l in m.loans}
    def colour(a):
        if id(a) in lenders and id(a) in borrowers: return "gold"
        if id(a) in lenders: return "tab:green"
        if id(a) in borrowers: return "tab:red"
        return "0.7"
    ax = fig.add_subplot(1, 5, i + 1)
    for l in m.loans:
        ax.plot([l.lender.x, l.borrower.x], [l.lender.y, l.borrower.y], color="0.5", lw=0.5)
    ax.scatter([a.x for a in m.agents], [a.y for a in m.agents], s=5, c=[colour(a) for a in m.agents])
    ax.set_title(f"t={t} n={len(m.agents)} loans={len(m.loans)}", fontsize=8)
    ax.set_xticks([]); ax.set_yticks([])
fig.tight_layout(); fig.savefig(out / "IV-A5-credit.png", dpi=70)
print("done")
