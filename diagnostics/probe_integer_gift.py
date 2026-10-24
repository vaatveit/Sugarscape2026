"""Rule S with integer gifts, as SugarscapeCW computes them (README fifth follow-up, 2026-10-23): each parent gives
int(initial endowment / 2), so the child's endowment, which is also its fertility requirement, is
int(e1 / 2) + int(e2 / 2) and can only round down. If the original program kept sugar as integers, p.55's "one half
of whatever his initial endowment had been" would truncate the same way. Run at p.55's threshold (1.0) on the
Chapter III population figures, with founders at spread ages (the default) and at age 0, against the same without
the truncation.

The wrapper calls rule S unchanged and then truncates: it refunds each parent the fraction above a whole unit and
gives the child the integer sum. Only the re-check of the initiating parent between births in one turn differs from
truncating inside the rule, by under half a unit. Diagnostic only: nothing here changes the model.

Usage: probe_integer_gift.py [seeds] [jobs]
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import math
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from experiments.registry import EXPERIMENTS
from experiments.run import sugarscape_metrics
from replication.report import evaluate
from replication.targets import TARGETS
from score_variant import fmt
from sugarscape.model import Model
from sugarscape.rules import sex

ORIGINAL_MATE = sex.mate
IDS = ("III-1", "III-3", "III-4", "III-5")
SETTINGS = {"exact, spread founders": ("exact", "uniform"), "integer, spread founders": ("integer", "uniform"),
            "exact, founders age 0": ("exact", "zero"), "integer, founders age 0": ("integer", "zero")}


def integer_mate(model, agent):
    children = ORIGINAL_MATE(model, agent)
    for child in children:
        others = [p for p in model.neighbors_of(agent) if child in p.children]
        if len(others) != 1:
            raise RuntimeError("could not identify the child's second parent")
        total = 0.0
        for parent in (agent, others[0]):
            half = parent.initial_sugar * model.config.child_share
            parent.sugar += half - math.floor(half)
            total += math.floor(half)
        child.sugar = child.initial_sugar = total
    return children


def run(args):
    name, exp_id, k = args
    gift, ages = SETTINGS[name]
    sex.mate = integer_mate if gift == "integer" else ORIGINAL_MATE  # workers are reused; reset every run
    exp = EXPERIMENTS[exp_id]
    model = Model(replace(exp.config, fertility_threshold=1.0, founder_ages=ages, seed=exp.config.seed + k))
    series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **sugarscape_metrics(m)}))
    return name, exp_id, k, series, np.mean([a.initial_sugar for a in model.agents]) if model.agents else math.nan


if __name__ == "__main__":
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(run, [(s, e, k) for s in SETTINGS for e in IDS
                                   for k in range(min(seeds, EXPERIMENTS[e].seeds))]))
    runs = {(s, e): [r for ss, ee, _, r, _ in sorted(done, key=lambda d: d[2]) if (ss, ee) == (s, e)]
            for s in SETTINGS for e in IDS}
    print(f"Rule S at p.55's threshold with exact or integer gifts, up to {seeds} seeds\n")
    print("| Target | Book | " + " | ".join(SETTINGS) + " |\n|---|---|" + "---|" * len(SETTINGS))
    for t in TARGETS:
        if t.experiment not in IDS or t.baseline:
            continue
        book = "—" if t.book_value is None else f"{t.book_value:g}"
        print(f"| {t.experiment} {t.name} | {book} | "
              + " | ".join(fmt(evaluate(t, runs[s, t.experiment], None)) for s in SETTINGS) + " |")
    print("\nMean endowment of the living at the end of III-1 (founders' mean is 75):")
    for s in SETTINGS:
        print(f"  {s}: {np.nanmean([d[4] for d in done if d[0] == s and d[1] == 'III-1']):.1f}")
