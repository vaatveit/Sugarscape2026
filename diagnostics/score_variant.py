"""Score a registered rule-S variant (experiments.registry.VARIANTS) on experiments outside its validation figures,
against the saved default runs cut to the same seeds (README next step, 2026-10-23: VAR-c1c3fit on VI-1).
Diagnostic only: the variant's settings are applied with dataclasses.replace; nothing is registered.

Usage: score_variant.py <variant> <exp_id,...> [seeds] [jobs]
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import math
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

from _paths import ROOT
from experiments.registry import EXPERIMENTS, VARIANTS
from experiments.run import load_results, results_current, sugarscape_metrics
from replication.report import evaluate
from replication.targets import TARGETS
from sugarscape.model import Model


def run(args):
    variant, exp_id, k = args
    exp = EXPERIMENTS[exp_id]
    model = Model(replace(exp.config, **VARIANTS[variant], seed=exp.config.seed + k))
    series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **sugarscape_metrics(m)}))
    return exp_id, k, series


def fmt(result):
    v = result.observed_mean
    return "—" if math.isnan(v) else f"{v:.3g} {result.status}" + (
        "" if result.n_valid == result.n_runs else f" ({result.n_valid}/{result.n_runs})")


if __name__ == "__main__":
    variant, ids = sys.argv[1], sys.argv[2].split(",")
    seeds = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(run, [(variant, e, k) for e in ids for k in range(min(seeds, EXPERIMENTS[e].seeds))]))
    runs = {e: [s for ee, _, s in sorted(done, key=lambda d: d[1]) if ee == e] for e in ids}
    default = {e: load_results(e, ROOT / "results")[:len(runs[e])] if results_current(e, ROOT / "results") else None
               for e in ids}
    print(f"VAR-{variant} settings {VARIANTS[variant]} on {', '.join(ids)}, {seeds} seeds\n")
    print(f"| Target | Book | Default | {variant} |\n|---|---|---|---|")
    for t in TARGETS:
        if t.experiment not in ids or (t.baseline and t.baseline not in ids):
            continue
        base = (runs[t.baseline], default[t.baseline]) if t.baseline else (None, None)
        d = "not run" if default[t.experiment] is None else fmt(evaluate(t, default[t.experiment], base[1]))
        book = "—" if t.book_value is None else f"{t.book_value:g}"
        print(f"| {t.experiment} {t.name} | {book} | {d} | {fmt(evaluate(t, runs[t.experiment], base[0]))} |")
