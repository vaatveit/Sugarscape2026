"""Score Ascape 5.6.1's Sugarscape sex model (Brookings) on our Chapter III population targets.

Runs come from ascape/AscapeRun.java via ascape/build_and_run.sh (see ascape/README.md): Ascape's own rules and agent
code with the figures' stated endowments and fertility ages, on Ascape's generated landscape with its 300 founders
("ascape") and on the book's map with our 400 ("book"). Targets that need metrics Ascape's rows don't carry are left
out.

Usage: ascape_compare.py <folder of fig3-N_<map>_seedK.csv>
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from pathlib import Path

import numpy as np

from _paths import ROOT
from experiments.run import load_results, results_current
from mason_compare import fmt, read
from replication.report import evaluate
from replication.targets import TARGETS

FIGURES = {"III-1": "fig3-1", "III-3": "fig3-3", "III-4": "fig3-4", "III-5": "fig3-5"}
MAPS = ("ascape", "book")

if __name__ == "__main__":
    folder = Path(sys.argv[1])
    ascape = {(e, m): [read(p) for p in sorted(folder.glob(f"{c}_{m}_seed*.csv"))]
              for e, c in FIGURES.items() for m in MAPS}

    def saved(exp_id):  # None until `python -m replication.report` has run it under the current settings
        return load_results(exp_id, ROOT / "results") if results_current(exp_id, ROOT / "results") else None

    ours = {e: saved(e) for e in FIGURES}
    book = {e: saved(f"VAR-book/{e}") for e in FIGURES}
    print("| Target | Book | Ascape, own landscape | Ascape, book map | Ours, p.55 (VAR-book) | Ours, default |")
    print("|---|---|---|---|---|---|")
    for t in TARGETS:
        if t.experiment not in FIGURES:
            continue
        try:
            a = [fmt(evaluate(t, ascape[(t.experiment, m)])) for m in MAPS]
        except KeyError:  # a metric Ascape's rows don't carry
            continue
        b = "—" if t.book_value is None else f"{t.book_value:g}"
        cells = ["not run" if runs[t.experiment] is None else fmt(evaluate(t, runs[t.experiment])) for runs in (book, ours)]
        print(f"| {t.experiment} {t.name} | {b} | " + " | ".join(a + cells) + " |")
    print()
    print("Trajectories (mean over seeds):")
    for (e, m), runs in ascape.items():
        p = np.array([[r["population"] for r in s] for s in runs])
        extinct = sum(row[-1] == 0 for row in p)
        print(f"  Ascape {e} {m} ({len(runs)} seeds): t=20 {p[:, 20].mean():.0f}, t=85 {p[:, 85].mean():.0f}, "
              f"min t<300 {p[:, :300].min(axis=1).mean():.0f}, mean t>=500 {p[:, 500:].mean():.0f}, "
              f"range t>=1000 {np.mean(p[:, 1000:].max(axis=1) - p[:, 1000:].min(axis=1)):.0f}, "
              f"extinct {extinct}/{len(runs)}")
