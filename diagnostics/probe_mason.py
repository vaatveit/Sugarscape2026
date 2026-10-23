"""Probe readings suggested by MASON's code and the book's p.65 wording.

O: mate before metabolizing (MASON's turn: move, mate, metabolize)
V: the current site is not a destination; stay only if no site in view has sugar (MASON's M)
T: p.65 "reduce the amount of sugar necessary for reproduction to the range 10 to 40":
   the fertility threshold is drawn from 10-40 while endowments stay 50-100 (III-4, III-5)
"""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import math
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

import sugarscape.model as model_mod
import sugarscape.rules.movement as movement
import sugarscape.rules.sex as sex
from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period
from sugarscape.model import Model

ORIG = (Model.step, movement.move, sex.is_fertile, sex.mate)


def step_mate_first(self):
    """Model.step for the Chapter III rule set (M, S only) with mating before metabolism."""
    cfg = self.config
    self.dead_this_step = []
    self.trade_log = []
    self.infection_log = []
    for agent in self.agents:
        agent.moved = False
    order = [self.agents[i] for i in self.rng.permutation(len(self.agents))]
    for agent in order:
        if not agent.alive:
            continue
        movement.move(self, agent)
        agent.neighbors = self.neighbors_of(agent)
        sex.mate(self, agent)
        movement.metabolize(self, agent)
    for agent in self.agents:
        agent.age += 1
    dying = [a for a in self.agents if a.age >= a.max_age]
    for agent in dying:
        self.die(agent, excluded_heirs=dying)
    self.landscape.growback(cfg.growback_rate)
    self.t += 1


def move_must(model, agent):
    """M without the current site as a candidate; stay only when nothing in view has sugar."""
    best = None
    for x, y, dist in movement.candidate_sites(model, agent)[1:]:
        score = movement.site_score(model, x, y)
        if score > 0 and (best is None or score > best[0] or (score == best[0] and dist < best[1])):
            best = (score, dist, x, y)
    if best is not None:
        agent.moved = True
        model.move_agent(agent, best[2], best[3])
    ls = model.landscape
    harvest = ls.sugar[agent.x, agent.y]
    agent.sugar += harvest
    ls.sugar[agent.x, agent.y] = 0.0
    agent.last_income = float(harvest)


def fertile_threshold(agent, threshold=1.0):  # flat MASON threshold replaces the scaled test; threshold unused
    return (agent.alive and agent.sex is not None and agent.fertility_start <= agent.age < agent.fertility_end
            and agent.sugar >= agent.repro_threshold)


THRESH_RNG = None


def mate_with_threshold(model, agent):
    kids = ORIG[3](model, agent)
    for k in kids:
        k.repro_threshold = float(THRESH_RNG.integers(10, 40, endpoint=True))
    return kids


STEPS = {"III-1": 1000, "III-3": 2500, "III-4": 600, "III-5": 1000}
VARIANTS = ["base", "O", "V", "OV", "T", "OT", "OVT"]


def run(args):
    global THRESH_RNG
    exp_id, variant, seed = args
    cfg = replace(EXPERIMENTS[exp_id].config, seed=seed)
    use_t = "T" in variant and exp_id in ("III-4", "III-5")
    if "T" in variant and exp_id not in ("III-4", "III-5"):
        return args, None
    if use_t:
        cfg = replace(cfg, endowment=(50, 100))
    try:
        if "O" in variant:
            Model.step = step_mate_first
        if "V" in variant:
            movement.move = move_must
        if use_t:
            THRESH_RNG = np.random.default_rng(777 + seed)
            sex.is_fertile = fertile_threshold
            sex.mate = mate_with_threshold
            model_mod.sex.mate = mate_with_threshold
        m = Model(cfg)
        if use_t:
            for a in m.agents:
                a.repro_threshold = float(THRESH_RNG.integers(10, 40, endpoint=True))
        pops = [len(m.agents)]
        for _ in range(STEPS[exp_id]):
            m.step()
            pops.append(len(m.agents))
            if len(m.agents) > 2400:
                pops += [len(m.agents)] * (STEPS[exp_id] + 1 - len(pops))
                break
        ever = m._next_id
    finally:
        Model.step, movement.move, sex.is_fertile, sex.mate = ORIG
        model_mod.sex.mate = ORIG[3]
    return args, (pops, ever)


def period(p, t0, t1):
    return dominant_period("population", t0, t1)([{"t": t, "population": float(v)} for t, v in enumerate(p)])


def summary(exp_id, rs):
    a = np.array([p for p, _ in rs], dtype=float)
    ever = np.mean([e for _, e in rs])
    if exp_id == "III-1":
        return " ".join(f"t{t}={a[:, t].mean():.0f}" for t in (20, 85, 240, 330)) + f" late={a[:, 500:].mean():.0f}"
    if exp_id == "III-3":
        per = [period(p, 300, 2500) for p, _ in rs]
        return (f"floor300+={a[:, 300:].min(1).mean():.0f} mean={a[:, 300:].mean():.0f} max300+={a[:, 300:].max(1).mean():.0f}"
                f" period={np.nanmean(per) if not all(map(math.isnan, per)) else float('nan'):.0f} agents_ever={ever:.0f}")
    if exp_id == "III-4":
        pk, tk = a[:, :151].max(1), a[:, :151].argmax(1)
        per = [period(p, 100, 600) for p, _ in rs]
        return (f"peak={pk.mean():.0f}@{tk.mean():.0f} trough={np.mean([p[int(t):].min() for p, t in zip(a, tk)]):.0f}"
                f" range300+={np.mean(a[:, 300:].max(1) - a[:, 300:].min(1)):.0f}"
                f" period={np.nanmean(per) if not all(map(math.isnan, per)) else float('nan'):.0f}")
    return f"extinct@1000={np.mean(a[:, -1] == 0):.2f} t200={a[:, 200].mean():.0f} max={a.max(1).mean():.0f}"


BOOK = {"III-1": "t20=470 t85=570 t240=415 t330=545 late=500",
        "III-3": "floor~250 period~200 agents_ever~12500 (fn 10)",
        "III-4": "amplitude >1000 falling to ~800, period ~125 (p.65); Fig: peak 1554@71 trough 343",
        "III-5": "extinct after three growth surges (p.65)"}

if __name__ == "__main__":
    tasks = [(e, v, s) for e in STEPS for v in VARIANTS for s in range(3)]
    with ProcessPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 8) as pool:
        out = [o for o in pool.map(run, tasks) if o[1] is not None]
    for e in STEPS:
        print(f"{e}  book: {BOOK[e]}")
        for v in VARIANTS:
            rs = [r for (e_, v_, _), r in out if e_ == e and v_ == v]
            if rs:
                print(f"   {v:5s} | {summary(e, rs)}", flush=True)
