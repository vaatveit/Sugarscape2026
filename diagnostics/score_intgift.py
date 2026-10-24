"""Integer gifts (VAR-intgift) combined with README candidates C1 and C3, on every population figure (III-1, III-3,
III-4, III-5, VI-2, VI-3), at p.55's threshold with nothing fitted (user request, 2026-10-23). Set beside the saved
runs of VAR-book (p.55 as written), VAR-intgift, VAR-c1c3fit and the default (threshold 0.83).

  +C1  mate search within vision (mate_contact="vision")
  +C3  Ascape's children: each parent gives at most 5 sugar, rounded down here, and the child's fertility threshold
       is a fresh draw from the founders' range (child_gift="capped", child_threshold="redraw"). The redraw cuts
       the link between the gift and the next generation's threshold, through which integer gifts act.

Founders are at spread ages throughout (the default, and C3's). Diagnostic only: the settings are applied with
dataclasses.replace; nothing is registered.

Usage: score_intgift.py [seeds] [jobs]
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

from _paths import ROOT
from experiments.registry import EXPERIMENTS, VALIDATION, VARIANTS
from experiments.run import load_results, results_current, sugarscape_metrics
from replication.report import evaluate
from replication.targets import TARGETS
from score_variant import fmt
from sugarscape.model import Model

INT = VARIANTS["intgift"]
C1 = {"mate_contact": "vision"}
C3 = {"child_gift": "capped", "child_threshold": "redraw"}
SETTINGS = {"intgift+C1": {**INT, **C1}, "intgift+C3": {**INT, **C3}, "intgift+C1+C3": {**INT, **C1, **C3}}
SAVED = {"VAR-book": "VAR-book/", "VAR-intgift": "VAR-intgift/", "VAR-c1c3fit": "VAR-c1c3fit/", "default": ""}


def run(args):
    name, exp_id, k = args
    exp = EXPERIMENTS[exp_id]
    model = Model(replace(exp.config, **SETTINGS[name], seed=exp.config.seed + k))
    series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **sugarscape_metrics(m)}))
    return name, exp_id, k, series


if __name__ == "__main__":
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(run, [(s, e, k) for s in SETTINGS for e in VALIDATION
                                   for k in range(min(seeds, EXPERIMENTS[e].seeds))]))
    runs = {(s, e): [r for ss, ee, _, r in sorted(done, key=lambda d: d[2]) if (ss, ee) == (s, e)]
            for s in SETTINGS for e in VALIDATION}

    def saved(exp_id):
        return load_results(exp_id, ROOT / "results") if results_current(exp_id, ROOT / "results") else None

    for label, prefix in SAVED.items():
        for e in VALIDATION:
            runs[label, e] = saved(prefix + e)
    columns = list(SAVED) + list(SETTINGS)
    print(f"Integer gifts with C1 and C3 at p.55's threshold (up to {seeds} seeds), beside saved runs\n")
    print("| Target | Book | " + " | ".join(columns) + " |\n|---|---|" + "---|" * len(columns))
    for t in TARGETS:
        if t.experiment not in VALIDATION:
            continue
        book = "—" if t.book_value is None else f"{t.book_value:g}"
        cells = []
        for c in columns:
            r, base = runs[c, t.experiment], runs[c, t.baseline] if t.baseline else None
            cells.append("not run" if r is None or (t.baseline and base is None) else fmt(evaluate(t, r, base)))
        print(f"| {t.experiment} {t.name} | {book} | " + " | ".join(cells) + " |")
