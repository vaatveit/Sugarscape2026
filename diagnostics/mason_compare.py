"""Score MASON's own Sugarscape (Bigbee, Cioffi-Revilla and Luke 2007) on our Chapter III population targets.

MASON's runs come from its own fig3-1 ... fig3-5 configs, built and run headless by mason/RunSeeded.java (see
mason/README.md). Its child placement ignores occupancy, and its III-4/III-5 configs read p.65 as a flat fertility
threshold (25 and 10 sugar). Rows use our driver's on-grid means; MASON's own vision/metabolism statistics average over
founders only. Targets that need metrics MASON's rows don't carry are left out.

Usage: mason_compare.py <folder of fig3-N_seedK.csv>
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import math
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from pathlib import Path

import numpy as np

from _paths import ROOT
from experiments.run import load_results, results_current
from replication.report import evaluate
from replication.targets import TARGETS

FIGURES = {"III-1": "fig3-1", "III-3": "fig3-3", "III-4": "fig3-4", "III-5": "fig3-5"}


def read(path):
    rows = []
    for line in path.read_text().splitlines():
        if line.startswith("RS,"):
            _, t, count, on_grid, vision, metabolism = line.split(",")
            rows.append({"t": int(t), "population": float(count), "on_grid": float(on_grid),
                         "mean_vision": float(vision), "mean_metabolism": float(metabolism)})
    return rows


def fmt(r):
    return "—" if math.isnan(r.observed_mean) else f"{r.observed_mean:.3g} {r.status}" + (
        "" if r.n_valid == r.n_runs else f" ({r.n_valid}/{r.n_runs})")


if __name__ == "__main__":
    folder = Path(sys.argv[1])
    mason = {e: [read(p) for p in sorted(folder.glob(f"{c}_seed*.csv"))] for e, c in FIGURES.items()}
    def saved(exp_id):  # None until `python -m replication.report` has run it under the current settings
        return load_results(exp_id, ROOT / "results") if results_current(exp_id, ROOT / "results") else None

    ours = {e: saved(e) for e in FIGURES}
    book = {e: saved(f"VAR-book/{e}") for e in FIGURES}
    print("| Target | Book | MASON | Ours, p.55 (VAR-book) | Ours, default |")
    print("|---|---|---|---|---|")
    for t in TARGETS:
        if t.experiment not in FIGURES:
            continue
        try:
            m = evaluate(t, mason[t.experiment])
        except KeyError:  # a metric MASON's rows don't carry
            continue
        b = "—" if t.book_value is None else f"{t.book_value:g}"
        cells = ["not run" if runs[t.experiment] is None else fmt(evaluate(t, runs[t.experiment])) for runs in (book, ours)]
        print(f"| {t.experiment} {t.name} | {b} | {fmt(m)} | " + " | ".join(cells) + " |")
    print()
    print("Trajectories (mean over seeds; book from the digitized figures):")
    for e, runs in mason.items():
        p = np.array([[r["population"] for r in s] for s in runs])
        ghost = np.mean([[r["population"] - r["on_grid"] for r in s] for s in runs])
        extinct = sum(row[-1] == 0 for row in p)
        print(f"  MASON {e} ({len(runs)} seeds): t=20 {p[:, 20].mean():.0f}, t=85 {p[:, 85].mean():.0f}, "
              f"min t<300 {p[:, :300].min(axis=1).mean():.0f}, mean t>=500 {p[:, 500:].mean():.0f}, "
              f"range t>=1000 {np.mean(p[:, 1000:].max(axis=1) - p[:, 1000:].min(axis=1)):.0f}, "
              f"extinct {extinct}/{len(runs)}, off-grid agents {ghost:.1f}")
