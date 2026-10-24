"""VAR-inttrade (whole units change hands in rule T) beside the default on every target of an experiment that
trades (Chapters IV and VI), from the saved runs (user request, 2026-10-23). Run the report first; this reads
results/ under the current defaults, so it pins no epoch. Diagnostic only: nothing is run or registered.

Usage: score_inttrade.py
"""
import math
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from collections import Counter

from _paths import ROOT
from experiments.registry import TRADE_VALIDATION
from experiments.run import load_results, results_current
from replication.report import evaluate
from replication.targets import TARGETS

RANK = {"fail": 0, "near": 1, "pass": 2}


def fmt(result):  # as score_variant's, which can't be imported here: it pins epoch C on import
    v = result.observed_mean
    return "—" if math.isnan(v) else f"{v:.3g} {result.status}" + (
        "" if result.n_valid == result.n_runs else f" ({result.n_valid}/{result.n_runs})")


def saved(exp_id):
    if not results_current(exp_id, ROOT / "results"):
        raise SystemExit(f"{exp_id}: no current saved runs; run python -m replication.report first")
    return load_results(exp_id, ROOT / "results")


if __name__ == "__main__":
    cache = {}

    def runs(exp_id):
        return cache.setdefault(exp_id, saved(exp_id)) if exp_id else None

    rows, totals, moves = [], {}, Counter()
    for t in TARGETS:
        if t.experiment not in TRADE_VALIDATION:
            continue
        v = next(u for u in TARGETS if u.experiment == f"VAR-inttrade/{t.experiment}" and u.name == t.name)
        a, b = evaluate(t, runs(t.experiment), runs(t.baseline)), evaluate(v, runs(v.experiment), runs(v.baseline))
        chapter = t.experiment.split("-")[0]
        for col, r in (("default", a), ("inttrade", b)):
            totals.setdefault((chapter, col), Counter())[r.status] += 1
        if a.status != b.status:
            moves["better" if RANK[b.status] > RANK[a.status] else "worse"] += 1
        book = "—" if t.book_value is None else f"{t.book_value:g}"
        mark = "" if a.status == b.status else (" ▲" if RANK[b.status] > RANK[a.status] else " ▼")
        rows.append(f"| {t.experiment} {t.name} | {book} | {fmt(a)} | {fmt(b)}{mark} |")
    print("Integer trade (VAR-inttrade) beside the default, every target of an experiment that trades\n")
    print("| Target | Book | Default | VAR-inttrade |\n|---|---|---|---|")
    print("\n".join(rows))
    print("\n| Chapter | Default pass / near / fail | VAR-inttrade pass / near / fail |\n|---|---|---|")
    for chapter in ("IV", "VI"):
        cells = [" / ".join(str(totals[chapter, c][s]) for s in ("pass", "near", "fail")) for c in ("default", "inttrade")]
        print(f"| {chapter} | {cells[0]} | {cells[1]} |")
    print(f"\nStatus changes: {moves['better']} better, {moves['worse']} worse")
