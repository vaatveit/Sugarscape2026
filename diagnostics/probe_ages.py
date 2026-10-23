"""Founders' starting ages: age 0 (current) vs U[0, max_age) (Animation III-1 frame 1, Fig III-1's start,
VI-2's early births, Ascape), each with the book's fertility test (1.0) and the calibrated 0.83."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py

import math
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from experiments.registry import EXPERIMENTS
from replication.targets import dominant_period
from sugarscape.model import Model

STEPS = {"III-1": 2500, "III-3": 2500, "III-4": 1000, "III-5": 1500, "VI-2": 200, "VI-3": 1000}
VARIANTS = [("age0", 1.0), ("uniform", 1.0), ("age0", 0.83), ("uniform", 0.83)]
CAP = 2450


def run(args):
    exp_id, (ages, thr), seed = args
    m = Model(replace(EXPERIMENTS[exp_id].config, seed=seed, fertility_threshold=thr))
    if ages == "uniform":
        rng = np.random.default_rng(10_000 + seed)
        for a in m.agents:
            a.age = int(rng.integers(0, int(a.max_age)))
    hist0 = np.histogram([a.age for a in m.agents], bins=range(0, 101, 10))[0].tolist()
    pops = [len(m.agents)]
    for _ in range(STEPS[exp_id]):
        m.step()
        pops.append(len(m.agents))
        if len(m.agents) > CAP:
            pops += [len(m.agents)] * (STEPS[exp_id] + 1 - len(pops))
            break
    hist_late = np.histogram([a.age for a in m.agents], bins=range(0, 101, 10))[0].tolist()
    return args, (pops, m.agents_ever, hist0, hist_late)


def period(p, t0, t1):
    return dominant_period("population", t0, t1)([{"t": t, "population": float(v)} for t, v in enumerate(p)])


def nanmean(xs):
    xs = [x for x in xs if not math.isnan(x)]
    return f"{np.mean(xs):.0f} ({len(xs)}/5)" if xs else "none"


def summary(exp_id, rs):
    a = np.array([r[0] for r in rs], dtype=float)
    if exp_id == "III-1":
        return (" ".join(f"t{t}={a[:, t].mean():.0f}" for t in (1, 20, 85, 240, 330))
                + f" late={a[:, 500:].mean():.0f} relsd={np.mean(a[:, 500:].std(1) / a[:, 500:].mean(1)):.3f}")
    if exp_id == "III-3":
        return (f"floor={a[:, 300:].min(1).mean():.0f} mean={a[:, 300:].mean():.0f} max={a[:, 300:].max(1).mean():.0f}"
                f" period={nanmean([period(p, 300, 2500) for p in a])} agents_ever={np.mean([r[1] for r in rs]):.0f}")
    if exp_id == "III-4":
        pk, tk = a[:, :201].max(1), a[:, :201].argmax(1)
        return (f"peak={pk.mean():.0f}@{tk.mean():.0f} trough={np.mean([p[int(t):int(t) + 150].min() for p, t in zip(a, tk)]):.0f}"
                f" range300+={np.mean(a[:, 300:].max(1) - a[:, 300:].min(1)):.0f} period={nanmean([period(p, 100, 1000) for p in a])}")
    if exp_id == "III-5":
        ext = [int(np.argmax(p == 0)) if (p == 0).any() else None for p in a]
        return f"extinct={np.mean([e is not None for e in ext]):.2f} at={[e for e in ext if e]} max={a.max(1).mean():.0f}"
    if exp_id == "VI-2":
        return " ".join(f"t{t}={a[:, t].mean():.0f}" for t in (10, 20, 40, 60, 100)) + f" extinct@200={np.mean(a[:, 200] == 0):.2f}"
    return (f"min40-120={a[:, 40:121].min(1).mean():.0f} peak150-300={a[:, 150:301].max(1).mean():.0f}"
            f" floor250+={a[:, 250:].min(1).mean():.0f} ceil250+={a[:, 250:].max(1).mean():.0f}"
            f" period={nanmean([period(p, 200, 1000) for p in a])}")


BOOK = {"III-1": "t1~417 t20=470 t85=570 t240=415 t330=545 late=500 relsd<0.10",
        "III-3": "floor~250 period~200 agents_ever~12500", "III-4": "peak 1554@71, trough 343, range~1000->800, period~125",
        "III-5": "extinct after three growth surges (Fig III-5: by t~500)", "VI-2": "t10=290 t20=130 t40=90 t60=50 t100=15 extinct",
        "VI-3": "min~65 peak~1190 floor~700 ceil~1200 period~115"}

if __name__ == "__main__":
    tasks = [(e, v, s) for e in STEPS for v in VARIANTS for s in range(5)]
    with ProcessPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 8) as pool:
        out = list(pool.map(run, tasks))
    for e in STEPS:
        print(f"{e}  book: {BOOK[e]}")
        for v in VARIANTS:
            rs = [r for (e_, v_, _), r in out if e_ == e and v_ == v]
            print(f"   {v[0]:7s} thr={v[1]:<4} | {summary(e, rs)}", flush=True)
    for v in VARIANTS:
        rs = [r for (e_, v_, _), r in out if e_ == "III-1" and v_ == v]
        print("III-1 age histogram", v, "t0:", np.mean([r[2] for r in rs], 0).round().astype(int).tolist(),
              "t2500:", np.mean([r[3] for r in rs], 0).round().astype(int).tolist())
    print("book Anim III-1 frames: [63,49,45,64,45,55,49,30,13,4] [66,54,72,71,73,63,60,45,26,5] "
          "[56,61,61,66,63,59,59,57,25,9] [52,70,71,63,67,64,65,47,13,6]")
