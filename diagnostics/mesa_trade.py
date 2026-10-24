"""Chapter IV under Mesa's Sugarscape G1MT departures (mesa/examples/advanced/sugarscape_g1mt, read 2026-10-23; the
same code as the SFI Complexity Explorer tutorial). Mesa's map file is identical to ours. Its departures from rules M
and T that bear on Chapter IV's misses (trade volume, Fig IV-6 at t=500):
  "partners": an agent trades with every agent within its vision, a diamond (|dx| + |dy| <= vision), instead of
              its four lattice neighbors (p.105);
  "diamond":  rule M looks over the same diamond instead of the four lattice directions; the agent's own site is a
              candidate only when nothing else is in sight (in Mesa an occupied cell, its own included, is never a
              candidate); ties go to the nearest by Euclidean distance, then at random.
Not reproduced here: Mesa's grid doesn't wrap, every agent moves before any trades, traded amounts are truncated to
integers, and founders may share a site. Diagnostic only: nothing here changes the model.

Usage: mesa_trade.py [seeds] [jobs]
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import math
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

from _paths import ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import load_results, results_current, sugarscape_metrics
from replication.report import evaluate
from replication.targets import TARGETS
from score_variant import fmt
from sugarscape.model import Model
from sugarscape.rules import movement, trade
from sugarscape.rules.movement import pollution_active, site_score, welfare_scorer

ORIGINAL_MOVE, ORIGINAL_TRADE = movement.move, trade.trade_with_neighbors
SETTINGS = {"registered": set(), "partners in vision": {"partners"}, "diamond movement": {"diamond"},
            "both": {"partners", "diamond"}}
IDS = ("IV-3", "IV-6/trade/v1", "IV-6/trade/v3", "IV-6/trade/v10", "IV-6/notrade/v3")


def diamond(model, agent):
    """(x, y, Euclidean distance) of the sites within |dx| + |dy| <= vision, own site excluded, wrapped."""
    ls, v = model.landscape, agent.vision
    return [(*ls.wrap(agent.x + dx, agent.y + dy), math.hypot(dx, dy))
            for dx in range(-v, v + 1) for dy in range(-v + abs(dx), v - abs(dx) + 1) if dx or dy]


def diamond_move(model, agent):
    score_at = welfare_scorer(model, agent) if model.config.spice else (lambda x, y: site_score(model, x, y))
    sites = [s for s in diamond(model, agent) if model.agent_at(s[0], s[1]) is None] or [(agent.x, agent.y, 0.0)]
    scores = [score_at(x, y) for x, y, _ in sites]
    top = [s for s, sc in zip(sites, scores) if math.isclose(sc, max(scores))]
    near = min(d for _, _, d in top)
    top = [s for s in top if math.isclose(s[2], near)]
    x, y, _ = top[int(model.rng.integers(len(top)))]
    agent.moved = (x, y) != (agent.x, agent.y)
    model.move_agent(agent, x, y)
    ls = model.landscape
    harvest = ls.sugar[x, y]
    agent.sugar += harvest
    ls.sugar[x, y] = 0.0
    agent.last_income = float(harvest)
    if model.config.spice:
        agent.spice += ls.spice[x, y]
        ls.spice[x, y] = 0.0
    if pollution_active(model):
        ls.pollution[x, y] += model.config.pollution[0] * harvest


def trade_in_vision(model, agent):
    partners = [p for x, y, _ in diamond(model, agent) if (p := model.agent_at(x, y)) is not None]
    for i in model.rng.permutation(len(partners)):
        model.trade_log.extend(trade.bargain(model, agent, partners[int(i)]))


def run(args):
    name, exp_id, k = args
    parts = SETTINGS[name]
    movement.move = diamond_move if "diamond" in parts else ORIGINAL_MOVE  # workers are reused; reset every run
    trade.trade_with_neighbors = trade_in_vision if "partners" in parts else ORIGINAL_TRADE
    exp = EXPERIMENTS[exp_id]
    model = Model(replace(exp.config, seed=exp.config.seed + k))
    series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **sugarscape_metrics(m)}))
    return name, exp_id, k, series


if __name__ == "__main__":
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(run, [(s, e, k) for s in SETTINGS for e in IDS for k in range(seeds)]))
    runs = {(s, e): [r for ss, ee, _, r in sorted(done, key=lambda d: d[2]) if (ss, ee) == (s, e)]
            for s in SETTINGS for e in IDS}
    print(f"Chapter IV under Mesa G1MT's departures, {seeds} seeds\n")
    print("| Target | Book | " + " | ".join(SETTINGS) + " |\n|---|---|" + "---|" * len(SETTINGS))
    for t in TARGETS:
        if t.experiment not in IDS or (t.baseline and t.baseline not in IDS):
            continue
        book = "—" if t.book_value is None else f"{t.book_value:g}"
        print(f"| {t.experiment} {t.name} | {book} | " + " | ".join(
            fmt(evaluate(t, runs[s, t.experiment], runs[s, t.baseline] if t.baseline else None)) for s in SETTINGS)
            + " |")
