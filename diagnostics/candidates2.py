"""Candidate departures C4-C7 of the README, each scored with the replication targets of the figures it bears on.
Diagnostic only: nothing here changes the model; each variant patches it from outside.

  C4  rule-by-rule sweeps (Kehoe's order): every agent moves and eats, in a random order, then every agent runs its
      other rules, in a fresh random order. The text implies one turn per agent (p.26)
  C5  growback before the agents move instead of after. Growback at the end of period t is growback at the start of
      t+1, so this only relabels the order; the script checks that the agents' series are identical
  C6  disease: a sick agent passes every active disease to each neighbor, not one chosen at random (departs from p.145)
  C7  credit: creditworthiness counts spice income as well as sugar income (harvest less metabolism of each good)

Runs use the registered configs (so the default threshold 0.83) and the registry's seeds, capped at SEEDS, and are
compared with the saved default runs cut to the same seeds ("not run" until `python -m replication.report` has run
them under the current settings). Results are cached in results/diagnostics-candidates2/.

Usage: candidates2.py [variant,...] [jobs]    variants: C4 C5 C6 C7 (default: all)
"""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
import math
import pickle
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈ and ≥
from concurrent.futures import ProcessPoolExecutor

from _paths import ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import load_results, results_current, run_seed
from replication.report import evaluate
from replication.targets import TARGETS
from sugarscape import model as model_module
from sugarscape.rules import combat, credit, culture, disease, movement, sex, trade

SEEDS = 5
FIGURES = {
    "C4": ("III-1", "III-3", "III-4", "III-5", "VI-2", "VI-3", "II-6", "III-12", "III-13"),
    "C6": ("V-1", "V-2", "VI-1"),
    "C7": ("VI-1",),
}
CACHE = ROOT / "results" / "diagnostics-candidates2"


def sweep_step(self):
    """Model.step with the agents' turn split in two sweeps: move and eat, then everything else."""
    cfg = self.config
    self.dead_this_step = []
    self.trade_log = []
    self.infection_log = []
    for agent in self.agents:
        agent.moved = False
    for agent in [self.agents[i] for i in self.rng.permutation(len(self.agents))]:
        if not agent.alive:
            continue
        if cfg.combat_alpha is not None:
            combat.combat_move(self, agent)
        else:
            movement.move(self, agent)
        movement.metabolize(self, agent)
    for agent in [self.agents[i] for i in self.rng.permutation(len(self.agents))]:
        if not agent.alive:
            continue
        agent.neighbors = self.neighbors_of(agent)
        if cfg.sex:
            sex.mate(self, agent)
        if cfg.culture:
            culture.transmit(self, agent)
            culture.update_friends(agent, agent.neighbors)
        if cfg.trade:
            trade.trade_with_neighbors(self, agent)
        if cfg.credit is not None:
            credit.seek_credit(self, agent)
        if cfg.disease_list:
            disease.transmit(self, agent)
            disease.immune_response(agent)
    _end_of_period(self)


def _end_of_period(self):
    """The tail of Model.step, unchanged: aging, old-age death, loans, replacement, then the environment."""
    cfg = self.config
    for agent in self.agents:
        agent.age += 1
    dying = [a for a in self.agents if a.age >= a.max_age]
    for agent in dying:
        self.die(agent, excluded_heirs=dying)
    if cfg.credit is not None:
        credit.settle_loans(self)
    if cfg.replacement:
        for dead in list(self.dead_this_step):
            self.spawn_random_agent(dead.tribe if cfg.replacement_same_tribe else None)
    if cfg.seasons is not None:
        beta, gamma = cfg.seasons
        self.landscape.seasonal_growback(self.t, cfg.growback_rate, beta, gamma, cfg.winter_growback)
    else:
        self.landscape.growback(cfg.growback_rate)
    if cfg.diffusion_period is not None and self.t >= cfg.diffusion_start and self.t % cfg.diffusion_period == 0:
        self.landscape.diffuse()
    self.t += 1


def growback_first_step(self):
    """Model.step with G1 growback moved to the start of the period (sugar-only, unseasoned runs)."""
    self.landscape.growback(self.config.growback_rate)
    original_growback = self.landscape.growback
    self.landscape.growback = lambda rate: None  # skip the end-of-period growback
    try:
        ORIGINAL_STEP(self)
    finally:
        self.landscape.growback = original_growback


def transmit_all(model, agent):
    """Rule E's transmission with every active disease passed to each neighbor."""
    if not agent.diseases:
        return
    neighbors = model.neighbors_of(agent)
    for i in model.rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        for d in list(agent.diseases):
            if other.immune is not None and disease.infect(other, d):
                model.infection_log.append((agent, other))


def move_with_spice_income(model, agent):
    before = agent.spice
    ORIGINAL_MOVE(model, agent)
    agent.last_spice_income = agent.spice - before - agent.spice_metabolism


def creditworthy_two_goods(model, borrower, amount_due):
    d, _ = credit._terms(model)
    owed = sum(loan.due for loan in model.loans if loan.borrower is borrower)
    income = borrower.last_income + getattr(borrower, "last_spice_income", 0.0)
    return income * d - owed >= amount_due


ORIGINAL_STEP = model_module.Model.step
ORIGINAL_MOVE = movement.move
PATCHES = {
    "C4": lambda: setattr(model_module.Model, "step", sweep_step),
    "C5": lambda: setattr(model_module.Model, "step", growback_first_step),
    "C6": lambda: setattr(disease, "transmit", transmit_all),
    "C7": lambda: (setattr(movement, "move", move_with_spice_income), setattr(credit, "creditworthy", creditworthy_two_goods)),
}


def run(args):
    variant, exp_id, k = args
    model_module.Model.step, movement.move = ORIGINAL_STEP, ORIGINAL_MOVE  # worker processes are reused: reset
    disease.transmit, credit.creditworthy = ORIGINAL_TRANSMIT, ORIGINAL_CREDITWORTHY
    if variant is not None:
        PATCHES[variant]()
    return variant, exp_id, k, run_seed(exp_id, k)


ORIGINAL_TRANSMIT, ORIGINAL_CREDITWORTHY = disease.transmit, credit.creditworthy


def fmt(result):
    v = result.observed_mean
    return "—" if math.isnan(v) else f"{v:.3g} {result.status}" + (
        "" if result.n_valid == result.n_runs else f" ({result.n_valid}/{result.n_runs})")


def check_c5(pool):
    """C5 against the unpatched model on II-6's first seed: the agents' series must match."""
    (_, _, _, patched), (_, _, _, plain) = pool.map(run, [("C5", "II-6", 0), (None, "II-6", 0)])
    keys = ("population", "ne_fraction", "mean_sugar", "gini", "moved", "mean_neighbors")
    same = all(a[key] == b[key] for a, b in zip(patched, plain) for key in keys if key in a)
    print(f"C5 (growback first) on II-6 seed 0: agents' series {'identical' if same else 'DIFFER'} "
          f"over {len(plain)} periods ({', '.join(k for k in keys if k in plain[0])})")


if __name__ == "__main__":
    names = sys.argv[1].split(",") if len(sys.argv) > 1 else ["C4", "C5", "C6", "C7"]
    jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    CACHE.mkdir(parents=True, exist_ok=True)
    scored = [v for v in names if v in FIGURES]
    todo = [(v, e, k) for v in scored for e in FIGURES[v] for k in range(min(SEEDS, EXPERIMENTS[e].seeds))
            if not (CACHE / f"{v}_{e}.pkl").exists()]
    with ProcessPoolExecutor(jobs) as pool:
        if "C5" in names:
            check_c5(pool)
        done = list(pool.map(run, todo))
    for v in scored:
        for e in FIGURES[v]:
            got = sorted((k, s) for vv, ee, k, s in done if vv == v and ee == e)
            if got:
                (CACHE / f"{v}_{e}.pkl").write_bytes(pickle.dumps([s for _, s in got]))
    for v in scored:
        runs = {e: pickle.loads((CACHE / f"{v}_{e}.pkl").read_bytes()) for e in FIGURES[v]}
        default = {e: load_results(e, ROOT / "results")[:SEEDS] if results_current(e, ROOT / "results") else None
                   for e in FIGURES[v]}
        print(f"\n{v}\n\n| Target | Book | Default | {v} |\n|---|---|---|---|")
        for t in TARGETS:
            if t.experiment not in FIGURES[v] or (t.baseline and t.baseline not in FIGURES[v]):
                continue
            base = (runs.get(t.baseline), default.get(t.baseline)) if t.baseline else (None, None)
            d = "not run" if default[t.experiment] is None else fmt(evaluate(t, default[t.experiment], base[1]))
            book = "—" if t.book_value is None else f"{t.book_value:g}"
            print(f"| {t.experiment} {t.name} | {book} | {d} | {fmt(evaluate(t, runs[t.experiment], base[0]))} |")
