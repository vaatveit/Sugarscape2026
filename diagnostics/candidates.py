"""Labelled departures from rule S (README candidates C1-C3), scored with the replication targets of every
population figure (III-1, III-3, III-4, III-5, VI-2, VI-3). Diagnostic only: nothing here changes the model.

  C1  mate search within vision: partners are agents in sight along the four lattice directions, not just the
      four neighbors; the child is still placed next to a parent
  C2  each parent gives half its current sugar (Kehoe's prose reading), and the child's fertility threshold is a
      fresh draw from the founders' endowment range, so children born poor come of age below threshold
  C3  Ascape's package: each parent gives at most 5 sugar, and the child's threshold is a fresh draw

Every variant uses p.55's fertility test (threshold 1.0) and founders at spread ages; spice gifts follow the sugar
rule. Seeds are the registry's, capped at SEEDS. Compared with the saved runs of VAR-book (p.55 as written) and the
default (threshold 0.83); columns without current saved runs show "not run" (run `python -m replication.report`).

Usage: candidates.py [variant,...] [jobs]    variants: C1 C2 C3 C1+C2 C1+C3 (default: all)
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import math
import pickle
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

from _paths import ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import load_results, results_current, sugarscape_metrics
from replication.report import evaluate
from replication.targets import TARGETS
from sugarscape.model import Model
from sugarscape.rules import sex
from sugarscape.rules.culture import cross_tags

FIGURES = ("III-1", "III-3", "III-4", "III-5", "VI-2", "VI-3")
SEEDS = 5
VARIANTS = {  # contact, gift, child's threshold
    "C1": ("vision", "book", "endowment"),
    "C2": ("neighbors", "current", "redraw"),
    "C3": ("neighbors", "ascape", "redraw"),
    "C1+C2": ("vision", "current", "redraw"),
    "C1+C3": ("vision", "ascape", "redraw"),
}
CACHE = ROOT / "results" / "diagnostics-candidates"


def in_sight(model, agent):
    """Agents within the agent's vision along the four lattice directions (rule M's lookout), nearest first."""
    found = []
    for k in range(1, agent.vision + 1):
        for dx, dy in sex.VON_NEUMANN:
            other = model.agent_at(agent.x + dx * k, agent.y + dy * k)
            if other is not None:
                found.append(other)
    return found


def make_mate(contact, gift, threshold):
    def gifts(parents, held, initial):
        if gift == "book":
            return [getattr(p, initial) / 2 for p in parents]
        if gift == "current":
            return [max(getattr(p, held), 0.0) / 2 for p in parents]
        return [min(5.0, max(getattr(p, held), 0.0)) for p in parents]

    def mate(model, agent):
        rng, cfg = model.rng, model.config
        children = []
        partners = in_sight(model, agent) if contact == "vision" else model.neighbors_of(agent)
        for i in rng.permutation(len(partners)):
            other = partners[int(i)]
            if other.sex is None or other.sex == agent.sex or not (
                sex.is_fertile(agent, cfg.fertility_threshold) and sex.is_fertile(other, cfg.fertility_threshold)
            ):
                continue
            sites = list(dict.fromkeys(sex._empty_sites(model, agent) + sex._empty_sites(model, other)))
            if not sites:
                continue
            x, y = sites[int(rng.integers(len(sites)))]
            parents = (agent, other)
            vision = parents[int(rng.integers(2))].vision
            metabolism = parents[int(rng.integers(2))].metabolism
            max_age = parents[int(rng.integers(2))].max_age
            g = gifts(parents, "sugar", "initial_sugar")
            for p, amount in zip(parents, g):
                p.sugar -= amount
            child = model.new_agent(x, y, vision, metabolism, sum(g), max_age)
            if threshold == "redraw":
                child.initial_sugar = float(rng.integers(cfg.endowment[0], cfg.endowment[1], endpoint=True))
            model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
            if agent.tags is not None and other.tags is not None:
                child.tags = cross_tags(rng, agent.tags, other.tags)
            if cfg.spice:
                s = gifts(parents, "spice", "initial_spice")
                for p, amount in zip(parents, s):
                    p.spice -= amount
                child.spice = child.initial_spice = sum(s)
                if threshold == "redraw":
                    lo, hi = cfg.spice_endowment or cfg.endowment
                    child.initial_spice = float(rng.integers(lo, hi, endpoint=True))
                child.spice_metabolism = parents[int(rng.integers(2))].spice_metabolism
                child.foresight = parents[int(rng.integers(2))].foresight
            agent.children.append(child)
            other.children.append(child)
            children.append(child)
        return children

    return mate


def run(args):
    variant, exp_id, k = args
    sex.mate = make_mate(*VARIANTS[variant])  # worker processes are reused: set it every time
    exp = EXPERIMENTS[exp_id]
    model = Model(replace(exp.config, fertility_threshold=1.0, seed=exp.config.seed + k))
    series = []
    model.run(exp.steps, observer=lambda m: series.append({"t": m.t, **sugarscape_metrics(m)}))
    return variant, exp_id, k, series


def fmt(result):
    v = result.observed_mean
    return "—" if math.isnan(v) else f"{v:.3g} {result.status}" + ("" if result.n_valid == result.n_runs else f" ({result.n_valid}/{result.n_runs})")


if __name__ == "__main__":
    names = sys.argv[1].split(",") if len(sys.argv) > 1 else list(VARIANTS)
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    CACHE.mkdir(parents=True, exist_ok=True)
    todo = [(v, e, k) for v in names for e in FIGURES for k in range(min(SEEDS, EXPERIMENTS[e].seeds))
            if not (CACHE / f"{v}_{e}.pkl").exists()]
    with ProcessPoolExecutor(jobs) as pool:
        done = list(pool.map(run, todo))
    for v in names:
        for e in FIGURES:
            got = sorted((k, s) for vv, ee, k, s in done if vv == v and ee == e)
            if got:
                (CACHE / f"{v}_{e}.pkl").write_bytes(pickle.dumps([s for _, s in got]))
    runs = {(v, e): pickle.loads((CACHE / f"{v}_{e}.pkl").read_bytes()) for v in names for e in FIGURES}
    for e in FIGURES:
        for label, exp_id in (("VAR-book", f"VAR-book/{e}"), ("default", e)):
            current = results_current(exp_id, ROOT / "results")  # else shown as "not run"
            runs[(label, e)] = load_results(exp_id, ROOT / "results")[:SEEDS] if current else None  # the candidates' seeds
    columns = ["VAR-book", "default"] + names
    print("| Target | Book | " + " | ".join(columns) + " |")
    print("|---|---|" + "---|" * len(columns))
    for t in TARGETS:
        if t.experiment not in FIGURES:
            continue
        cells = []
        for c in columns:
            if runs[(c, t.experiment)] is None:
                cells.append("not run")
                continue
            base = runs.get((c, t.baseline)) if t.baseline else None
            cells.append(fmt(evaluate(t, runs[(c, t.experiment)], base)))
        book = "—" if t.book_value is None else f"{t.book_value:g}"
        print(f"| {t.experiment} {t.name} | {book} | " + " | ".join(cells) + " |")
