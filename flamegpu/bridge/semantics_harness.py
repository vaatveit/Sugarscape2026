"""Python's model with the GPU's turn semantics, to measure what they change (spec 2026-10-25-gpu-full-parity, "What
was measured", and section 8).

Every agent's target is fixed at the start of the period by deferred acceptance: serial dictatorship in the period's
order over the sites free at the start, scored with the holdings at the start. Then the agents take their turns in
order exactly as Python does (move to the target, harvest, metabolise, S, K, T, L, E), except that a child is never
born on the target of an agent still to come. Combat runs are refused: the GPU runs combat exactly in order.

Usage: python -m bridge.semantics_harness <id-or-prefix>... [--jobs J] [--out DIR]
Seeds base + 1000 + k for k < the registered count (a stream of their own), registered steps, into results-harness/
in experiments.run's layout, so `python -m bridge.agreement_report --gpu results-harness` scores them against Python.
"""

import argparse
import csv
import time
from dataclasses import replace
from multiprocessing import Pool
from pathlib import Path

from bridge.gpu_run import matching_ids
from bridge.paths import SUGARSCAPE_ROOT  # noqa: F401  (puts the Python project on sys.path)
from experiments.registry import EXPERIMENTS
from experiments.run import experiment_config, fingerprint, result_dir, sugarscape_metrics
from sugarscape.model import Model
from sugarscape.rules import credit, culture, disease, movement, sex, trade

HARNESS_FINGERPRINT = "semantics-harness\n"
SEED_OFFSET = 1000
_python_empty_sites = sex._empty_sites


def _empty_sites(model, agent):
    """Python's sex._empty_sites, without the targets of agents still to come (the GPU's difference 2)."""
    reserved = getattr(model, "pending_targets", None)
    sites = _python_empty_sites(model, agent)
    return [s for s in sites if not reserved or s not in reserved]


sex._empty_sites = _empty_sites  # a no-op for every model but HybridModel, which alone sets pending_targets


def _target(model, agent, taken):
    """Rule M's choice among the sites free at the start of the period and not taken by an agent earlier in the order."""
    score_at = (movement.welfare_scorer(model, agent) if model.config.spice
                else (lambda x, y: movement.site_score(model, x, y)))
    best = None
    for x, y, dist in movement.candidate_sites(model, agent):  # nobody has moved yet: occupancy is the start's
        if dist and (x, y) in taken:
            continue
        s = score_at(x, y)
        if best is None or s > best[0] or (s == best[0] and dist < best[1]):
            best = (s, dist, x, y)
    return best[2], best[3]


def _go_to(model, agent, x, y):
    """The effects of movement.move after its choice: move there and harvest."""
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
    if movement.pollution_active(model):
        alpha, _ = model.config.pollution
        ls.pollution[x, y] += alpha * harvest


class HybridModel(Model):
    def step(self):
        cfg = self.config
        if cfg.combat_alpha is not None:
            raise ValueError("the harness has no combat: the GPU runs combat exactly in Python's order")
        self.dead_this_step, self.trade_log, self.infection_log = [], [], []
        for a in self.agents:
            a.moved = False
        order = [self.agents[i] for i in self.rng.permutation(len(self.agents))]
        targets, taken = {}, set()
        for a in order:
            x, y = _target(self, a, taken)
            targets[a.id] = (x, y)
            if (x, y) != (a.x, a.y):
                taken.add((x, y))
        self.pending_targets = set(taken)
        for a in order:  # Model.step's turn, with the move fixed in advance
            if not a.alive:
                continue
            x, y = targets[a.id]
            self.pending_targets.discard((x, y))
            _go_to(self, a, x, y)
            movement.metabolize(self, a)
            if not a.alive:
                continue
            a.neighbors = self.neighbors_of(a)
            if cfg.sex:
                sex.mate(self, a)
            if cfg.culture:
                culture.transmit(self, a)
                culture.update_friends(a, a.neighbors)
            if cfg.trade:
                trade.trade_with_neighbors(self, a)
            if cfg.credit is not None:
                credit.seek_credit(self, a)
            if cfg.disease_list:
                disease.transmit(self, a)
                disease.immune_response(a)
        self.pending_targets = set()
        # The end of the period, as Model.step.
        for a in self.agents:
            a.age += 1
        dying = [a for a in self.agents if a.age >= a.max_age]
        for a in dying:
            self.die(a, excluded_heirs=dying)
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
            for _ in range(cfg.diffusion_passes):
                self.landscape.diffuse()
        self.t += 1


def run_seed(out: Path, exp_id: str, k: int, steps: int | None = None) -> int:
    """Seed k of an experiment through the harness, written as experiments.run writes seed{k}.csv."""
    exp = EXPERIMENTS[exp_id]
    cfg = experiment_config(exp_id)
    model = HybridModel(replace(cfg, seed=cfg.seed + SEED_OFFSET + k))
    rows = [{"t": 0, **sugarscape_metrics(model)}]
    for _ in range(exp.steps if steps is None else steps):
        model.step()
        rows.append({"t": model.t, **sugarscape_metrics(model)})
    folder = result_dir(exp_id, Path(out))
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / f"seed{k}.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows({key: repr(v) for key, v in r.items()} for r in rows)
    (folder / "fingerprint.txt").write_text(HARNESS_FINGERPRINT + fingerprint(exp_id), encoding="utf-8")
    return k


def _run(args):
    return run_seed(*args)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ids", nargs="+")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--out", type=Path, default=Path("results-harness"))
    args = parser.parse_args(argv)
    ids = [i for a in args.ids for i in matching_ids(a, EXPERIMENTS)
           if EXPERIMENTS[i].config.__class__.__name__ == "Config" and EXPERIMENTS[i].config.combat_alpha is None]
    tasks = sorted(((args.out, i, k) for i in ids for k in range(EXPERIMENTS[i].seeds)),
                   key=lambda t: -EXPERIMENTS[t[1]].steps)  # longest first
    start = time.time()
    with Pool(max(1, args.jobs)) as pool:
        for n, _ in enumerate(pool.imap_unordered(_run, tasks), 1):
            if n % 20 == 0 or n == len(tasks):
                print(f"{n}/{len(tasks)} seeds, {time.time() - start:.0f} s", flush=True)


if __name__ == "__main__":
    main()
