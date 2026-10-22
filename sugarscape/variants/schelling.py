"""The Schelling segregation variant of Chapter VI (pp.165-170, Animations VI-4 to VI-7).

Red and Blue agents on a 50x50 torus, 20% of sites vacant. An agent is satisfied when the
share of its von Neumann neighbors that share its color is at least its preference. A
dissatisfied agent moves to an acceptable empty site chosen at random, not the nearest one
(p.166). With finite lifetimes, an agent reaching its maximum age leaves and is replaced by a
new agent of random color at a random site that satisfies it (p.166, fn 11).
"""

import math
from collections.abc import Callable
from dataclasses import dataclass

import numpy as np

COLORS = ("red", "blue")
VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))


@dataclass(frozen=True)
class SchellingConfig:
    width: int = 50  # p.166: 50x50 torus
    height: int = 50
    population: int = 2000  # p.166: 20% of sites vacant
    preference: tuple[float, float] = (0.25, 0.25)  # uniform range of minimum like shares (p.166, p.170)
    max_age: tuple[int, int] | None = None  # None: infinite lifetimes (VI-4); (80, 100) for VI-5..VI-7
    seed: int = 0

    def __post_init__(self) -> None:
        if not 0 <= self.population <= self.width * self.height:
            raise ValueError(f"population {self.population} must fit the {self.width}x{self.height} lattice")
        lo, hi = self.preference
        if not 0 <= lo <= hi <= 1:
            raise ValueError(f"preference range {self.preference} must satisfy 0 <= low <= high <= 1")
        if self.max_age is not None and not 1 <= self.max_age[0] <= self.max_age[1]:
            raise ValueError(f"max_age range {self.max_age} must satisfy 1 <= low <= high")


@dataclass(eq=False)
class Resident:
    x: int
    y: int
    color: str  # "red" | "blue"
    preference: float
    max_age: float  # math.inf without lifetimes
    age: int = 0
    moved: bool = False  # moved this period


class SchellingModel:
    def __init__(self, config: SchellingConfig) -> None:
        self.config = config
        self.rng = np.random.default_rng(config.seed)
        self._grid: list[list[Resident | None]] = [[None] * config.height for _ in range(config.width)]
        self.agents: list[Resident] = []
        self.t = 0
        self.replaced_this_step = 0
        sites = [(x, y) for x in range(config.width) for y in range(config.height)]
        for i in self.rng.choice(len(sites), size=config.population, replace=False):
            color, preference, max_age = self._draw_traits()
            self.place(*sites[int(i)], color, preference, max_age)

    # --- occupancy -----------------------------------------------------------------------

    def place(self, x: int, y: int, color: str, preference: float, max_age: float = math.inf) -> Resident:
        x, y = x % self.config.width, y % self.config.height
        if self._grid[x][y] is not None:
            raise ValueError(f"site ({x}, {y}) is occupied")
        agent = Resident(x, y, color, preference, max_age)
        self._grid[x][y] = agent
        self.agents.append(agent)
        return agent

    def agent_at(self, x: int, y: int) -> Resident | None:
        return self._grid[x % self.config.width][y % self.config.height]

    def like_share(self, agent: Resident, x: int, y: int) -> float | None:
        """Share of `agent`'s color among the occupants of the four sites around (x, y), never
        counting `agent` itself (a site next to its own is judged as if it had left); None
        when there are no neighbors."""
        like = total = 0
        for dx, dy in VON_NEUMANN:
            other = self.agent_at(x + dx, y + dy)
            if other is None or other is agent:
                continue
            total += 1
            like += other.color == agent.color
        return like / total if total else None

    def satisfied(self, agent: Resident, x: int | None = None, y: int | None = None) -> bool:
        """At least `preference` of its neighbors share its color; no neighbors counts as
        satisfied (our call: 0/0 makes no demand)."""
        share = self.like_share(agent, agent.x if x is None else x, agent.y if y is None else y)
        return share is None or share >= agent.preference

    def acceptable_sites(self, agent: Resident) -> list[tuple[int, int]]:
        cfg = self.config
        return [
            (x, y)
            for x in range(cfg.width)
            for y in range(cfg.height)
            if self._grid[x][y] is None and self.satisfied(agent, x, y)
        ]

    # --- time ----------------------------------------------------------------------------

    def step(self) -> None:
        """Every agent acts once in a fresh random order; then aging and replacement (p.166)."""
        self.replaced_this_step = 0
        for agent in self.agents:
            agent.moved = False
        order = [self.agents[i] for i in self.rng.permutation(len(self.agents))]
        for agent in order:
            if self.satisfied(agent):
                continue
            sites = self.acceptable_sites(agent)
            if sites:
                self._move(agent, *sites[int(self.rng.integers(len(sites)))])

        for agent in self.agents:
            agent.age += 1
        leaving = [a for a in self.agents if a.age >= a.max_age]
        for agent in leaving:
            self._grid[agent.x][agent.y] = None
            self.agents.remove(agent)
        for _ in leaving:
            self._replace()
        self.replaced_this_step = len(leaving)
        self.t += 1

    def run(self, steps: int, observer: Callable[["SchellingModel"], None] | None = None) -> None:
        if observer:
            observer(self)
        for _ in range(steps):
            self.step()
            if observer:
                observer(self)

    # --- helpers -------------------------------------------------------------------------

    def _draw_traits(self) -> tuple[str, float, float]:
        cfg = self.config
        color = COLORS[int(self.rng.integers(2))]  # "approximately equal numbers" (p.166)
        preference = float(self.rng.uniform(*cfg.preference))
        if cfg.max_age is None:
            return color, preference, math.inf
        return color, preference, int(self.rng.integers(cfg.max_age[0], cfg.max_age[1], endpoint=True))

    def _move(self, agent: Resident, x: int, y: int) -> None:
        self._grid[agent.x][agent.y] = None
        self._grid[x][y] = agent
        agent.x, agent.y, agent.moved = x, y, True

    def _replace(self) -> None:
        """A newcomer of random color at a random site satisfying its preference, or any empty
        site when none does (our call)."""
        color, preference, max_age = self._draw_traits()
        newcomer = Resident(-1, -1, color, preference, max_age)
        sites = self.acceptable_sites(newcomer)
        if not sites:
            cfg = self.config
            sites = [(x, y) for x in range(cfg.width) for y in range(cfg.height) if self._grid[x][y] is None]
        x, y = sites[int(self.rng.integers(len(sites)))]
        self.place(x, y, color, preference, max_age)


def schelling_metrics(model: SchellingModel) -> dict[str, float]:
    """Population, colors, segregation, satisfaction and movement this period.

    `like_fraction` is the mean like share over agents with at least one neighbor; a random
    board gives about 0.5 (our measure: the book shows only pictures).
    """
    agents = model.agents
    shares = [s for a in agents if (s := model.like_share(a, a.x, a.y)) is not None]
    return {
        "population": float(len(agents)),
        "n_red": float(sum(a.color == "red" for a in agents)),
        "like_fraction": float(np.mean(shares)) if shares else math.nan,
        "fraction_satisfied": sum(model.satisfied(a) for a in agents) / len(agents) if agents else math.nan,
        "moved": float(sum(a.moved for a in agents)),
        "replaced": float(model.replaced_this_step),
    }
