"""III-5: births through each fall (peak -> trough): first and second half, mothers' ages, fertile-age women,
the share holding their threshold, and their net income. Also the births in the 60 periods before each trough."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
import ast
import sys
import numpy as np
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules.sex import is_fertile

STEPS = 1500


def run(args):
    seed, extra = args
    m = Model(replace(EXPERIMENTS["III-5"].config, seed=seed, **extra))
    th = m.config.fertility_threshold
    rows = []
    for t in range(STEPS):
        w = [a for a in m.agents if a.sex == "F" and a.fertility_start <= a.age < a.fertility_end]
        wf = sum(is_fertile(a, th) for a in w)
        inc = np.mean([a.last_income for a in w]) if w else np.nan
        before = {a.id: len(a.children) for a in m.agents if a.sex == "F"}
        ages = {a.id: a.age for a in m.agents}
        ids = m._next_id
        m.step()
        born = m._next_id - ids
        mages = [ages[a.id] for a in m.agents + m.dead_this_step if a.id in before and len(a.children) > before[a.id]
                 for _ in range(len(a.children) - before[a.id])]
        rows.append((len(m.agents), born, len(w), wf, inc, np.mean(mages) if mages else np.nan))
        if not m.agents:
            break
    return seed, np.array(rows, float)


def falls(p):
    s = np.convolve(p, np.ones(9) / 9, "same")
    pk = [t for t in range(60, len(s) - 60) if s[t] == s[t - 50:t + 51].max() and s[t] - s[t - 50:t + 51].min() > 300]
    out = []
    for a in pk:
        z = a + int(np.argmin(s[a:a + 150]))
        out.append((a, z))
    return out


if __name__ == "__main__":
    extra = ast.literal_eval(sys.argv[1]) if len(sys.argv) > 1 else {}
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(run, [(s, extra) for s in range(10)]))
    print(f"III-5 {extra}: each fall (peak -> trough)")
    print("  seed  peak@t -> trough@t | births/period 1st half, 2nd half | fertile-age women, share holding threshold, their net income (1st half) | mean mother age | births in 60 periods before the trough")
    allf = []
    for s, r in res:
        if r[-1, 0] == 0:
            print(f"  seed {s}: extinct at t={len(r)}")
        for a, z in falls(r[:, 0]):
            h = (a + z) // 2
            allf.append(r[a:z, 1].sum())
            print(f"  {s:4d}  {r[a,0]:5.0f}@{a} -> {r[z,0]:4.0f}@{z} | {r[a:h,1].mean():5.1f}, {r[h:z,1].mean():5.1f} | "
                  f"{r[a:h,2].mean():4.0f}, {np.nanmean(r[a:h,3] / np.maximum(r[a:h,2], 1)):.2f}, {np.nanmean(r[a:h,4]):+.2f} | "
                  f"{np.nanmean(r[a:z,5]):4.1f} | {r[max(0, z - 60):z, 1].sum():4.0f}")
