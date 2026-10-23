"""What keeps VAR-c1c3fit's societies from near-extinction after a peak (README next step 3, 2026-10-23)?

Runs III-5 (endowments 10-40, fertility ending 10 years earlier) under a rule-S setting and measures each fall against
what the book's troughs need (Chapter III record, "III-5's extinction": troughs of ≈50, so ≲1 birth per period in the
60 periods before a trough). For each fall (peak to trough of the 41-period moving average, swing ≥ 200): the peak and
trough of the raw series, births per period in the 60 periods before the trough, and starvations. For each cohort,
by the population when it was born: how it comes of age, as sugar over its fertility requirement (threshold times
initial_sugar) at the first period of its fertile window, and the share that qualify then.

Settings: "c1c3fit" is the registered variant (experiments.registry.VARIANTS). "lost" is the same with Ascape's exact
children (each parent pays min(5, sugar) but the child keeps only the second gift); "move" adds Ascape's movement
(candidates.ascape_move: occupied sites compete, and an agent whose best site is occupied stays put); "lost+move" both.
"fresh" draws each child's metabolism from the founders' range instead of a parent's, so selection can't remove
high metabolisms (a test of food-limited peaks, not a reading of the book). Each of these runs at the threshold given.
Food-limit settings (README next step, 2026-10-23; departures from the text, diagnostics only): "mustmove" counts an
agent's own site only when no other site is in sight (rule M otherwise unchanged); "lowland" zeroes every capacity-1
site; "slow<a>" grows sugar back at a per period instead of 1 (e.g. slow0.5). Tokens combine with "+".
Diagnostic only: nothing here changes the model.

Usage: probe_falls.py [setting] [theta] [seeds] [jobs] [figure: III-5|III-3|III-4]
       probe_falls.py fit <setting> <theta,...> [jobs]    (III-1's steady population, the fitting target; 5 seeds)
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import sys
sys.stdout.reconfigure(encoding="utf-8")  # the docstring's ≈ and ≲ may be printed
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from candidates import ascape_move, make_mate
from experiments.registry import EXPERIMENTS, VARIANTS
from experiments.run import sugarscape_metrics
from replication.targets import TARGETS
from sugarscape.model import Model
from sugarscape.rules import movement, sex

ORIGINAL_MATE, ORIGINAL_MOVE = sex.mate, movement.move
BIRTH_BINS = (0, 400, 700, 1000, 10**9)
STEADY = next(t for t in TARGETS if t.experiment == "III-1" and t.name == "steady population")


def must_move(model, agent):
    """Rule M with the agent's own site a candidate only when no other site is in sight: nearest of the richest
    unoccupied sites, ties at equal distance to the first encountered (fn 9)."""
    sites = movement.candidate_sites(model, agent)
    if len(sites) > 1:
        sites = sites[1:]
    best = None
    for x, y, dist in sites:
        score = movement.site_score(model, x, y)
        if best is None or score > best[0] or (score == best[0] and dist < best[1]):
            best = (score, dist, x, y)
    _, _, x, y = best
    agent.moved = (x, y) != (agent.x, agent.y)
    model.move_agent(agent, x, y)
    ls = model.landscape
    harvest = ls.sugar[x, y]
    agent.sugar += harvest
    ls.sugar[x, y] = 0.0
    agent.last_income = float(harvest)


def fresh_metabolism(mate):
    def wrapped(model, agent):
        children = mate(model, agent)
        lo, hi = model.config.metabolism
        for child in children:
            child.metabolism = int(model.rng.integers(lo, hi, endpoint=True))
        return children
    return wrapped


def build(setting, theta, exp_id, k):
    """VAR-c1c3fit's model of exp_id, seed k, with the setting's patches (module-level patches are reset first, since
    worker processes are reused)."""
    parts = setting.split("+")
    sex.mate = make_mate("vision", "lost", "redraw") if "lost" in parts else ORIGINAL_MATE
    movement.move = ascape_move if "move" in parts else must_move if "mustmove" in parts else ORIGINAL_MOVE
    if "fresh" in parts:
        sex.mate = fresh_metabolism(sex.mate)
    cfg = replace(EXPERIMENTS[exp_id].config, **VARIANTS["c1c3fit"], seed=EXPERIMENTS[exp_id].config.seed + k)
    if setting != "c1c3fit":
        cfg = replace(cfg, fertility_threshold=theta)
    for part in parts:
        if part.startswith("slow"):
            cfg = replace(cfg, growback_rate=float(part[4:]))
    m = Model(cfg)
    if "lowland" in parts:
        low = m.landscape.capacity == 1
        m.landscape.capacity[low] = 0
        m.landscape.sugar[low] = 0.0
    return m


def steady(args):
    setting, theta, k = args
    m = build(setting, theta, "III-1", k)
    series = []
    m.run(EXPERIMENTS["III-1"].steps, observer=lambda model: series.append({"t": model.t, **sugarscape_metrics(model)}))
    return theta, STEADY.statistic(series)


def run(args):
    setting, theta, exp_id, k = args
    base = EXPERIMENTS[exp_id]
    m = build(setting, theta, exp_id, k)
    cfg = m.config
    born_at = {}  # agent id -> population when born
    pop, births, starved, aged, coming, metab = [], [], [], [], [], []  # coming: (population at birth, sugar / requirement)
    for t in range(base.steps):
        before = m.agents_ever
        n = len(m.agents)
        pop.append(n)
        metab.append(np.mean([a.metabolism for a in m.agents]) if n else np.nan)
        if n == 0:
            births.append(0), starved.append(0), aged.append(0)
            continue
        m.step()
        births.append(m.agents_ever - before)
        for a in m.agents:
            if a.id >= before:
                born_at[a.id] = n
            elif a.sex is not None and a.age == a.fertility_start and a.id in born_at:
                coming.append((born_at[a.id], a.sugar / (cfg.fertility_threshold * a.initial_sugar)))
        dead = m.dead_this_step
        aged.append(sum(a.age >= a.max_age for a in dead))
        starved.append(len(dead) - aged[-1])
    return np.array(pop), np.array(births), np.array(starved), np.array(coming).reshape(-1, 2), np.array(metab)


def falls(pop, swing=200, window=41):
    """(peak t, trough t) pairs of the moving average's zigzag, mapped to the raw series' extremes nearby."""
    ma = np.convolve(pop, np.ones(window) / window, mode="valid")
    turns, direction = [], 0
    high = low = 0  # running extremes since the last turn; both tracked until the first swing sets a direction
    for i in range(1, len(ma)):
        if direction >= 0:
            high = i if ma[i] > ma[high] else high
            if ma[high] - ma[i] >= swing:
                turns.append(("peak", high))  # now falling
                direction, low = -1, i
                continue
        if direction <= 0:
            low = i if ma[i] < ma[low] else low
            if ma[i] - ma[low] >= swing:
                turns.append(("trough", low))  # now rising
                direction, high = 1, i
    pairs = []
    for (a, i), (b, j) in zip(turns, turns[1:]):
        if a == "peak" and b == "trough":
            lo, hi = i, j + window
            pairs.append((lo + int(np.argmax(pop[lo:lo + window])), lo + int(np.argmin(pop[lo:hi]))))
    return pairs


def fit(setting, grid, jobs):
    seeds = EXPERIMENTS["III-1"].seeds
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(steady, [(setting, theta, k) for theta in grid for k in range(seeds)]))
    print(f"{setting}, III-1 steady population (target {STEADY.book_value:g}), {seeds} seeds")
    for theta in grid:
        values = [v for th, v in done if th == theta]
        print(f"  theta {theta:g}: {np.nanmean(values):.0f}  (seeds: {', '.join(f'{v:.0f}' for v in values)})")


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "fit":
    fit(sys.argv[2], [float(x) for x in sys.argv[3].split(",")], int(sys.argv[4]) if len(sys.argv) > 4 else 8)
elif __name__ == "__main__":
    setting = sys.argv[1] if len(sys.argv) > 1 else "c1c3fit"
    theta = float(sys.argv[2]) if len(sys.argv) > 2 else VARIANTS["c1c3fit"]["fertility_threshold"]
    seeds = int(sys.argv[3]) if len(sys.argv) > 3 else 10
    jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    exp_id = sys.argv[5] if len(sys.argv) > 5 else "III-5"
    with ProcessPoolExecutor(jobs) as pool:
        res = list(pool.map(run, [(setting, theta, exp_id, k) for k in range(seeds)]))
    print(f"{exp_id}, setting {setting}" + (f" (theta {theta:g})" if setting != "c1c3fit" else "") + f", {seeds} seeds")
    extinct = sum(p[-1] == 0 for p, *_ in res)
    starved_total = sum(int(s.sum()) for _, _, s, *_ in res)
    print(f"extinct by t={len(res[0][0])}: {extinct}/{seeds}; lowest population after t=150, per seed: "
          f"{sorted(int(p[150:].min()) for p, *_ in res)}")
    print(f"starvations in all {seeds} runs: {starved_total}")
    rows = []
    for p, b, s, _, mu in res:
        for i, j in falls(p):
            pre = slice(max(j - 60, i), j)
            rows.append((p[i], p[j], b[pre].mean(), s[i:j].sum(), j - i, mu[i]))
    if rows:
        r = np.array(rows, float)
        print(f"falls: {len(r)}; peak median {np.median(r[:, 0]):.0f}; trough min / median {r[:, 1].min():.0f} / "
              f"{np.median(r[:, 1]):.0f}; births per period in the 60 before the trough, median "
              f"{np.median(r[:, 2]):.1f} (range {r[:, 2].min():.1f}-{r[:, 2].max():.1f}; book ≲1); starvations per fall "
              f"median {np.median(r[:, 3]):.0f}; fall length median {np.median(r[:, 4]):.0f}; mean metabolism at the peak "
              f"median {np.median(r[:, 5]):.2f}")
    coming = np.vstack([c for _, _, _, c, _ in res])
    print("coming of age, by population at birth: cohort size, median sugar / requirement, share qualifying")
    for lo, hi in zip(BIRTH_BINS, BIRTH_BINS[1:]):
        c = coming[(coming[:, 0] >= lo) & (coming[:, 0] < hi), 1]
        if len(c):
            print(f"  born at N {lo}-{hi if hi < 10**9 else '':}: {len(c)}, {np.median(c):.2f}, {np.mean(c >= 1):.2f}")
