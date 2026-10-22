"""Ring World, Chapter VI (pp.170-176, Animations VI-8 and VI-9).

Sugar harvesters on a ring of sites. Each period every agent, in random order, inspects the
unoccupied sites within its vision in the counterclockwise direction only (increasing index
here), goes to the nearest one with the most sugar, and eats it. Sugar grows back at unit
rate to capacity. There is no death, birth, or accumulation (p.172). Agents nonetheless form
traveling groups by leapfrogging; a group can be no larger than its most nearsighted member
can see across (p.175).
"""

import math
from collections.abc import Callable
from dataclasses import dataclass

import numpy as np

PLACEMENTS = ("random", "block")


@dataclass(frozen=True)
class RingConfig:
    sites: int = 150  # p.172
    capacity: int = 4  # p.172
    initial_sugar: tuple[int, int] = (0, 4)  # uniform integers (p.172; integer levels our call)
    population: int = 40  # p.172
    vision: tuple[int, int] = (15, 30)  # p.172
    placement: str = "random"  # "random" (VI-8) | "block": one contiguous group (VI-9, p.174)
    growback_rate: float = 1.0  # "unit rate" (p.172)
    seed: int = 0

    def __post_init__(self) -> None:
        if not 0 <= self.population <= self.sites:
            raise ValueError(f"population {self.population} must fit {self.sites} sites")
        lo, hi = self.vision
        if not 1 <= lo <= hi < self.sites:
            raise ValueError(f"vision range {self.vision} must satisfy 1 <= low <= high < sites")
        lo, hi = self.initial_sugar
        if not 0 <= lo <= hi <= self.capacity:
            raise ValueError(f"initial_sugar {self.initial_sugar} must lie within 0..capacity {self.capacity}")
        if self.placement not in PLACEMENTS:
            raise ValueError(f"placement must be one of {PLACEMENTS}, not {self.placement!r}")


@dataclass(eq=False)
class Harvester:
    position: int
    vision: int
    advanced: int = 0  # sites moved counterclockwise this period


class RingModel:
    def __init__(self, config: RingConfig) -> None:
        self.config = config
        self.rng = np.random.default_rng(config.seed)
        lo, hi = config.initial_sugar
        self.sugar = self.rng.integers(lo, hi, size=config.sites, endpoint=True).astype(float)
        self._occupant: list[Harvester | None] = [None] * config.sites
        self.agents: list[Harvester] = []
        self.t = 0
        n = config.population
        if config.placement == "block":
            start = int(self.rng.integers(config.sites))
            positions = [(start + i) % config.sites for i in range(n)]
        else:
            positions = [int(p) for p in self.rng.choice(config.sites, size=n, replace=False)]
        for p in positions:
            self.place(p, int(self.rng.integers(config.vision[0], config.vision[1], endpoint=True)))

    def place(self, position: int, vision: int) -> Harvester:
        position %= self.config.sites
        if self._occupant[position] is not None:
            raise ValueError(f"site {position} is occupied")
        agent = Harvester(position, vision)
        self._occupant[position] = agent
        self.agents.append(agent)
        return agent

    def agent_at(self, position: int) -> Harvester | None:
        return self._occupant[position % self.config.sites]

    def choose_site(self, agent: Harvester) -> int | None:
        """The nearest unoccupied site with the most sugar among the `vision` sites ahead; None
        when every site in view is occupied (p.172).

        Unlike the main model's M, the agent's own site is not a candidate: "each agent moves
        once each time period" (p.172) and lone agents keep "hopping along" (p.172), so an agent
        with a free site in view always moves; it stays only when its whole view is occupied
        (p.175). Our reading; it decides whether a loner trailing a group's eaten wake moves.
        """
        best = None  # (sugar, site); strict > keeps the nearest on ties
        for d in range(1, agent.vision + 1):
            site = (agent.position + d) % self.config.sites
            if self._occupant[site] is None and (best is None or self.sugar[site] > best[0]):
                best = (self.sugar[site], site)
        return None if best is None else best[1]

    def step(self) -> None:
        """Agents move once each in random order and eat where they end up; then sugar grows
        back at unit rate to capacity (p.172)."""
        cfg = self.config
        for agent in self.agents:
            agent.advanced = 0
        for i in self.rng.permutation(len(self.agents)):
            agent = self.agents[int(i)]
            site = self.choose_site(agent)
            if site is not None:  # a full field of view leaves the agent where it is (p.175)
                self._occupant[agent.position] = None
                self._occupant[site] = agent
                agent.advanced = (site - agent.position) % cfg.sites
                agent.position = site
            self.sugar[agent.position] = 0.0
        np.minimum(self.sugar + cfg.growback_rate, cfg.capacity, out=self.sugar)
        self.t += 1

    def run(self, steps: int, observer: Callable[["RingModel"], None] | None = None) -> None:
        if observer:
            observer(self)
        for _ in range(steps):
            self.step()
            if observer:
                observer(self)


def groups(model: RingModel, gap: int = 1) -> list[list[Harvester]]:
    """Maximal runs of agents around the ring with at most `gap` empty sites between consecutive
    members (our definition; random call order opens small gaps inside a group, fn 13)."""
    n_sites = model.config.sites
    ordered = sorted(model.agents, key=lambda a: a.position)
    if len(ordered) <= 1:
        return [ordered] if ordered else []
    # Empty sites between each agent and the next one counterclockwise, wrapping past the seam.
    gaps = [(ordered[(i + 1) % len(ordered)].position - a.position - 1) % n_sites for i, a in enumerate(ordered)]
    breaks = [i for i, g in enumerate(gaps) if g > gap]
    if not breaks:
        return [ordered]
    start = breaks[0] + 1
    runs, current = [], []
    for k in range(len(ordered)):
        i = (start + k) % len(ordered)
        current.append(ordered[i])
        if gaps[i] > gap:
            runs.append(current)
            current = []
    return runs


def _mean(values: list[float]) -> float:
    return float(np.mean(values)) if values else math.nan


def ring_metrics(model: RingModel, gap: int = 1) -> dict[str, float]:
    """Group statistics for Animations VI-8 and VI-9: a group is a run of two or more agents."""
    runs = groups(model, gap)
    clusters = [r for r in runs if len(r) >= 2]
    sizes = [len(r) for r in clusters]
    population = len(model.agents)
    grouped = [a.advanced for r in clusters for a in r]
    alone = [r[0].advanced for r in runs if len(r) == 1]
    speed_grouped, speed_alone = _mean(grouped), _mean(alone)
    if math.isnan(speed_grouped) or math.isnan(speed_alone) or speed_alone == 0:
        speed_ratio = math.nan
    else:
        speed_ratio = speed_grouped / speed_alone
    return {
        "population": float(population),
        "n_groups": float(len(clusters)),
        "largest_group": float(max((len(r) for r in runs), default=0)),
        "mean_group_size": population / len(runs) if runs else math.nan,
        "group_size_cv": float(np.std(sizes) / np.mean(sizes)) if len(sizes) >= 2 else math.nan,
        "clustered_fraction": sum(sizes) / population if population else math.nan,
        "within_vision_bound": _mean([float(len(r) <= min(a.vision for a in r)) for r in clusters]),
        "speed_grouped": speed_grouped,
        "speed_alone": speed_alone,
        "speed_ratio": speed_ratio,
    }
