"""Score SugarscapeCW 1.2.0 (Christopher Watts, NetLogo; CoMSES codebase 4688) on our Chapter III population targets.

Runs come from sugarscapecw/CWRun.java via sugarscapecw/build_and_run.sh (see sugarscapecw/README.md): Watts' own
rule code, converted to NetLogo 6 syntax, from his Chapter III preset with each figure's stated endowment and
fertility ages, founders at age 0 (his presets, "zero") or at U[0, 80] (his option, "spread"). A run that dies out
stops printing, so it is padded with zeros to the figure's length. Targets that need metrics the rows don't carry are
left out.

Usage: sugarscapecw_compare.py <folder of fig3-N_<founders>_seedK.csv>
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from pathlib import Path

import numpy as np

from _paths import ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import load_results, results_current
from mason_compare import fmt, read
from replication.report import evaluate
from replication.targets import TARGETS

FIGURES = {"III-1": "fig3-1", "III-3": "fig3-3", "III-4": "fig3-4", "III-5": "fig3-5"}
FOUNDERS = ("zero", "spread")


def padded(path, steps):
    rows = read(path)
    if rows and rows[-1]["population"] == 0:
        nan = float("nan")
        rows += [{"t": t, "population": 0.0, "on_grid": 0.0, "mean_vision": nan, "mean_metabolism": nan}
                 for t in range(rows[-1]["t"] + 1, steps + 1)]
    return rows


if __name__ == "__main__":
    folder = Path(sys.argv[1])
    cw = {(e, f): [padded(p, EXPERIMENTS[e].steps) for p in sorted(folder.glob(f"{c}_{f}_seed*.csv"))]
          for e, c in FIGURES.items() for f in FOUNDERS}

    def saved(exp_id):  # None until `python -m replication.report` has run it under the current settings
        return load_results(exp_id, ROOT / "results") if results_current(exp_id, ROOT / "results") else None

    ours = {e: saved(e) for e in FIGURES}
    book = {e: saved(f"VAR-book/{e}") for e in FIGURES}
    print("| Target | Book | SugarscapeCW, founders age 0 | SugarscapeCW, spread ages | Ours, p.55 (VAR-book) | Ours, default |")
    print("|---|---|---|---|---|---|")
    for t in TARGETS:
        if t.experiment not in FIGURES:
            continue
        try:
            a = [fmt(evaluate(t, cw[(t.experiment, f)])) for f in FOUNDERS]
        except KeyError:  # a metric the rows don't carry
            continue
        b = "—" if t.book_value is None else f"{t.book_value:g}"
        cells = ["not run" if runs[t.experiment] is None else fmt(evaluate(t, runs[t.experiment])) for runs in (book, ours)]
        print(f"| {t.experiment} {t.name} | {b} | " + " | ".join(a + cells) + " |")
    print()
    print("Trajectories (mean over seeds):")
    for (e, f), runs in cw.items():
        p = np.array([[r["population"] for r in s] for s in runs])
        extinct = [next(r["t"] for r in s if r["population"] == 0) for s in runs if s[-1]["population"] == 0]
        print(f"  SugarscapeCW {e} {f} ({len(runs)} seeds): t=20 {p[:, 20].mean():.0f}, t=85 {p[:, 85].mean():.0f}, "
              f"min t<300 {p[:, :300].min(axis=1).mean():.0f}, mean t>=500 {p[:, 500:].mean():.0f}, "
              f"range t>=1000 {np.mean(p[:, 1000:].max(axis=1) - p[:, 1000:].min(axis=1)):.0f}, "
              f"extinct {len(extinct)}/{len(runs)}" + (f" (at t={sorted(extinct)})" if extinct else ""))
