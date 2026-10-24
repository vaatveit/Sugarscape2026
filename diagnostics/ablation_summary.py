"""Score ablation runs of the outside Sugarscapes (sugarscapecw/ablate.sh, nkremerh/ablate.py) on the Chapter III
targets they bear on: III-1's level, III-3's floor and period, III-4's range and period.

Usage: ablation_summary.py <root folder> <glob pattern with {fig} and {v}> <variant,...>
  e.g. ablation_summary.py <work>/ablate "fig3-{fig}_{v}_seed*.csv" base,nostack,wrap,nostack+wrap
       ablation_summary.py <work> "{v}/runs/fig3-{fig}_book_seed*.csv" base,ownsite,nobirth,sexages,both,all
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈
from pathlib import Path

import numpy as np

from experiments.registry import EXPERIMENTS
from mason_compare import fmt
from replication.report import evaluate
from replication.targets import TARGETS
from sugarscapecw_compare import padded

WANT = {("III-1", "steady population"), ("III-3", "population floor"), ("III-3", "oscillation period"),
        ("III-4", "oscillation range"), ("III-4", "oscillation period")}

if __name__ == "__main__":
    root, pattern, variants = Path(sys.argv[1]), sys.argv[2], sys.argv[3].split(",")
    for v in variants:
        cells, n = [], set()
        for fig in ("1", "3", "4"):
            exp = f"III-{fig}"
            files = sorted(root.glob(pattern.format(fig=fig, v=v)))
            if not files:
                continue
            n.add(len(files))
            runs = [padded(p, EXPERIMENTS[exp].steps) for p in files]
            cells += [f"{exp} {t.name} {fmt(evaluate(t, runs))}" for t in TARGETS
                      if t.experiment == exp and (t.experiment, t.name) in WANT]
            if fig == "1":
                p = np.array([[r["population"] for r in s] for s in runs])
                cells.append(f"III-1 at t=20 / 85: {p[:, 20].mean():.0f} / {p[:, 85].mean():.0f}")
        print(f"{v} ({'/'.join(map(str, sorted(n)))} seeds): " + "; ".join(cells))
