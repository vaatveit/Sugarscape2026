"""Should integer gifts replace the fitted 0.83 in the defaults (user request, 2026-10-23)? Every experiment the
fertility threshold touches (rule S, and credit, whose lending requirement uses it) is rerun under p.55's threshold
(1.0) with exact gifts, with integer gifts (gift_rounding="down"), and with integer gifts and partners in sight
(VAR-intgiftc1's settings, mate_contact="vision"), and every one of their targets is scored beside
the saved default runs (threshold 0.83). A baseline experiment outside the set uses its saved run. The default-wide
totals are recomputed with the candidate in place of the default. Diagnostic only: nothing here changes the defaults.

Usage: default_candidate.py [jobs]
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

from _paths import ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import load_results, results_current, sugarscape_metrics
from replication.report import evaluate
from replication.targets import TARGETS
from score_variant import fmt
from sugarscape.model import Model

CANDIDATES = {"p.55 (θ=1.0)": {"fertility_threshold": 1.0},
              "integer gifts (θ=1.0)": {"fertility_threshold": 1.0, "gift_rounding": "down"},
              "integer gifts + C1 (θ=1.0)": {"fertility_threshold": 1.0, "gift_rounding": "down",
                                             "mate_contact": "vision"}}
AFFECTED = tuple(e for e, x in EXPERIMENTS.items() if not e.startswith(("VAR-", "TEST-"))
                 and (getattr(x.config, "sex", False) or getattr(x.config, "credit", None) is not None))


def run(args):
    name, exp_id, k = args
    exp = EXPERIMENTS[exp_id]
    model = Model(replace(exp.config, **CANDIDATES[name], seed=exp.config.seed + k))
    series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **sugarscape_metrics(m)}))
    return name, exp_id, k, series


if __name__ == "__main__":
    jobs = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(run, [(c, e, k) for c in CANDIDATES for e in AFFECTED
                                   for k in range(EXPERIMENTS[e].seeds)]))
    runs = {(c, e): [r for cc, ee, _, r in sorted(done, key=lambda d: d[2]) if (cc, ee) == (c, e)]
            for c in CANDIDATES for e in AFFECTED}

    def saved(exp_id):
        if not results_current(exp_id, ROOT / "results"):
            raise SystemExit(f"saved runs of {exp_id} are not current: run python -m replication.report first")
        return load_results(exp_id, ROOT / "results")

    targets = [t for t in TARGETS if not t.experiment.startswith(("VAR-", "TEST-"))]
    columns = ["default (θ=0.83)", *CANDIDATES]
    results = {}
    for t in targets:
        base_saved = saved(t.baseline) if t.baseline else None
        results[t, columns[0]] = evaluate(t, saved(t.experiment), base_saved)
        for c in CANDIDATES:
            if t.experiment in AFFECTED:
                base = runs[c, t.baseline] if t.baseline in AFFECTED else base_saved
                results[t, c] = evaluate(t, runs[c, t.experiment], base)
            else:
                results[t, c] = results[t, columns[0]]
    print(f"Defaults: the fitted 0.83 against p.55's threshold with exact gifts, integer gifts, or integer gifts and C1. Rerun: {', '.join(AFFECTED)}\n")
    print("| Target | Book | " + " | ".join(columns) + " |\n|---|---|" + "---|" * len(columns))
    for t in targets:
        if t.experiment in AFFECTED:
            book = "—" if t.book_value is None else f"{t.book_value:g}"
            print(f"| {t.experiment} {t.name} | {book} | " + " | ".join(fmt(results[t, c]) for c in columns) + " |")
    print("\nTotals over all non-variant targets (pass / near / fail):")
    for c in columns:
        n = Counter(results[t, c].status for t in targets)
        m = Counter(results[t, c].status for t in targets if t.experiment in AFFECTED)
        print(f"  {c}: {n['pass']} / {n['near']} / {n['fail']} of {len(targets)}"
              f"  (affected experiments: {m['pass']} / {m['near']} / {m['fail']} of {sum(m.values())})")
    for c in CANDIDATES:
        print(f"\nStatus changes, default -> {c}:")
        for t in targets:
            a, b = results[t, columns[0]].status, results[t, c].status
            if a != b:
                print(f"  {t.experiment} {t.name}: {a} -> {b} ({fmt(results[t, columns[0]])} -> {fmt(results[t, c])})")
