"""III-3: per-mountain birth rate against the mountain's head count (Allee effect?), t=50-1000, both founder settings.
Also: does anyone ever re-found an emptied mountain?"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules.sex import is_fertile

BINS = (0, 10, 20, 40, 80, 120, 160, 240, 1000)


def side(a):
    return "NE" if a.x >= 25 and a.y >= 25 else ("SW" if a.x < 25 and a.y < 25 else None)


def run(args):
    founders, seed = args
    m = Model(replace(EXPERIMENTS["III-3"].config, founder_ages=founders, seed=seed))
    th = m.config.fertility_threshold
    acc = defaultdict(lambda: np.zeros(5))  # bin -> [agent-periods, births, fertile agent-periods, fertile with partner adjacent, fertile-age agent-periods]
    empty_since = {}
    refounded = 0
    for t in range(1000):
        counts = {"NE": 0, "SW": 0}
        fert = {"NE": 0, "SW": 0}; partnered = {"NE": 0, "SW": 0}; fage = {"NE": 0, "SW": 0}
        for a in m.agents:
            s = side(a)
            if s:
                counts[s] += 1
                if a.fertility_start <= a.age < a.fertility_end:
                    fage[s] += 1
                if is_fertile(a, th):
                    fert[s] += 1
                    if any(o.sex not in (None, a.sex) and is_fertile(o, th) for o in m.neighbors_of(a)):
                        partnered[s] += 1
        for s in counts:
            if counts[s] == 0:
                empty_since.setdefault(s, t)
            elif s in empty_since and counts[s] >= 10:
                refounded += 1; empty_since.pop(s)
        ids = m._next_id
        m.step()
        born = {"NE": 0, "SW": 0}
        for a in m.agents:
            if a.id >= ids and side(a):
                born[side(a)] += 1
        if t >= 50:
            for s in counts:
                b = np.digitize(counts[s], BINS) - 1
                acc[b] += (counts[s], born[s], fert[s], partnered[s], fage[s])
    return dict(acc), refounded, empty_since


if __name__ == "__main__":
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(f, s) for f in ("uniform", "zero") for s in range(8)]))
    tot = defaultdict(lambda: np.zeros(5))
    for acc, _, _ in res:
        for b, v in acc.items():
            tot[b] += v
    print("mountain head count | agent-periods | births per agent per period | fertile share | fertile with a fertile partner adjacent | fertile share of fertile-age")
    for b in sorted(tot):
        ap, br, fe, pa, fa = tot[b]
        if ap:
            print(f"  {BINS[b]:4d}-{BINS[b+1]:<4d} | {ap:8.0f} | {br / ap:.4f} | {fe / ap:.3f} | {pa / max(fe, 1):.3f} | {fe / max(fa, 1):.3f}")
    print("re-foundings (emptied quadrant back to >=10 agents):", sum(r for _, r, _ in res), "; still empty at t=1000:",
          sum(len(e) for _, _, e in res), "mountains in", len(res), "runs")
