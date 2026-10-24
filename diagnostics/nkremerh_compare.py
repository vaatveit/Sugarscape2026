"""Score nkremerh/sugarscape (Nathan Kremer-Herman, Python) on our Chapter III population targets.

Runs come from nkremerh/run.py: the repository's own rule code and Chapter III example, with each figure's stated
endowment and fertility ages, on its generated landscape ("own") and on the book's map ("book"). "III-4 preset" and
"III-5 preset" are the repository's own examples for those figures, which set starting sugar 20-80 where p.65 says
10-40; they are scored against the same figure's targets. A run that dies out is padded with zeros to its length.

Usage: nkremerh_compare.py <folder of fig3-N_<map>_seedK.csv>
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from pathlib import Path

import numpy as np

from _paths import ROOT
from experiments.run import load_results, results_current
from mason_compare import fmt
from replication.report import evaluate
from replication.targets import TARGETS
from sugarscapecw_compare import padded
from experiments.registry import EXPERIMENTS

FIGURES = {"III-1": "fig3-1", "III-3": "fig3-3", "III-4": "fig3-4", "III-5": "fig3-5",
           "III-4 preset": "fig3-4preset", "III-5 preset": "fig3-5preset"}
MAPS = ("own", "book")

if __name__ == "__main__":
    folder = Path(sys.argv[1])
    nk = {(e, m): [padded(p, EXPERIMENTS[e.split()[0]].steps) for p in sorted(folder.glob(f"{c}_{m}_seed*.csv"))]
          for e, c in FIGURES.items() for m in MAPS}

    def saved(exp_id):  # None until `python -m replication.report` has run it under the current settings
        return load_results(exp_id, ROOT / "results") if results_current(exp_id, ROOT / "results") else None

    ours = {e: saved(e) for e in FIGURES if " " not in e}
    book = {e: saved(f"VAR-book/{e}") for e in FIGURES if " " not in e}
    print("| Target | Book | nkremerh, own landscape | nkremerh, book map | Ours, p.55 (VAR-book) | Ours, default |")
    print("|---|---|---|---|---|---|")
    for label in FIGURES:
        exp_id = label.split()[0]
        for t in TARGETS:
            if t.experiment != exp_id:
                continue
            try:
                a = [fmt(evaluate(t, nk[(label, m)])) for m in MAPS]
            except KeyError:  # a metric the rows don't carry
                continue
            b = "—" if t.book_value is None else f"{t.book_value:g}"
            cells = (["—", "—"] if " " in label else
                     ["not run" if runs[exp_id] is None else fmt(evaluate(t, runs[exp_id])) for runs in (book, ours)])
            print(f"| {label} {t.name} | {b} | " + " | ".join(a + cells) + " |")
    print()
    print("Trajectories (mean over seeds):")
    for (e, m), runs in nk.items():
        p = np.array([[r["population"] for r in s] for s in runs])
        extinct = [next(r["t"] for r in s if r["population"] == 0) for s in runs if s[-1]["population"] == 0]
        print(f"  nkremerh {e} {m} ({len(runs)} seeds): t=20 {p[:, 20].mean():.0f}, t=85 {p[:, 85].mean():.0f}, "
              f"min t<300 {p[:, :300].min(axis=1).mean():.0f}, mean t>=500 {p[:, 500:].mean():.0f}, "
              f"range t>=1000 {np.mean(p[:, 1000:].max(axis=1) - p[:, 1000:].min(axis=1)):.0f}, "
              f"extinct {len(extinct)}/{len(runs)}" + (f" (at t={sorted(extinct)})" if extinct else ""))
