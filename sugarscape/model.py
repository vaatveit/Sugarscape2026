"""The model: agents on a landscape, advanced one period at a time by `step()`."""

import math
from collections.abc import Callable

import numpy as np

from sugarscape.agent import Agent
from sugarscape.config import Config
from sugarscape.landscape import Landscape
from sugarscape.maps import load_map
from sugarscape.rules import movement

VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))


class Model:
    def __init__(self, config: Config, capacity: np.ndarray | None = None) -> None:
        self.config = config
        self.rng = np.random.default_rng(config.seed)
        if capacity is None:
            capacity = load_map(config.sugar_map)
        if capacity.shape != (config.width, config.height):
            raise ValueError(f"capacity shape {capacity.shape} != ({config.width}, {config.height})")
        self.landscape = Landscape(capacity)
        self._grid: list[list[Agent | None]] = [[None] * config.height for _ in range(config.width)]
        self.agents: list[Agent] = []
        self.t = 0
        self.deaths_this_step = 0
        self._next_id = 0
        self._place_initial_population()

    # --- occupancy -----------------------------------------------------------------------

    def agent_at(self, x: int, y: int) -> Agent | None:
        x, y = self.landscape.wrap(x, y)
        return self._grid[x][y]

    def neighbors_of(self, agent: Agent) -> list[Agent]:
        """Living agents on the four von Neumann sites around `agent` (p.39)."""
        found = (self.agent_at(agent.x + dx, agent.y + dy) for dx, dy in VON_NEUMANN)
        return [a for a in found if a is not None]

    def random_empty_site(self) -> tuple[int, int] | None:
        empty = [
            (x, y)
            for x in range(self.config.width)
            for y in range(self.config.height)
            if self._grid[x][y] is None
        ]
        if not empty:
            return None
        return empty[int(self.rng.integers(len(empty)))]

    def new_agent(
        self, x: int, y: int, vision: int, metabolism: int, sugar: float, max_age: float = math.inf
    ) -> Agent:
        x, y = self.landscape.wrap(x, y)
        if self._grid[x][y] is not None:
            raise ValueError(f"site ({x}, {y}) is occupied")
        agent = Agent(
            id=self._next_id,
            x=x,
            y=y,
            vision=vision,
            metabolism=metabolism,
            sugar=float(sugar),
            initial_sugar=float(sugar),
            max_age=max_age,
        )
        self._next_id += 1
        self._grid[x][y] = agent
        self.agents.append(agent)
        return agent

    def spawn_random_agent(self) -> Agent:
        """A new agent with random genetics, endowment, and max age at a random empty site (R, p.32)."""
        site = self.random_empty_site()
        if site is None:
            raise ValueError("no empty site for a new agent: the lattice is full")
        return self._spawn_at(*site)

    def move_agent(self, agent: Agent, x: int, y: int) -> None:
        x, y = self.landscape.wrap(x, y)
        if (x, y) == (agent.x, agent.y):
            return
        if self._grid[x][y] is not None:
            raise ValueError(f"site ({x}, {y}) is occupied")
        self._grid[agent.x][agent.y] = None
        self._grid[x][y] = agent
        agent.x, agent.y = x, y

    def kill(self, agent: Agent) -> None:
        agent.alive = False
        self._grid[agent.x][agent.y] = None
        self.agents.remove(agent)
        self.deaths_this_step += 1

    # --- time ----------------------------------------------------------------------------

    def step(self) -> None:
        """One period, in the order fixed by the design (docs/superpowers/specs, Scheduling)."""
        cfg = self.config
        self.deaths_this_step = 0
        for agent in self.agents:
            agent.moved = False

        # Agents act one at a time in a fresh random order each period (p.26).
        order = [self.agents[i] for i in self.rng.permutation(len(self.agents))]
        for agent in order:
            if not agent.alive:
                continue
            movement.move(self, agent)
            movement.metabolize(self, agent)
            if agent.alive:
                agent.neighbors = self.neighbors_of(agent)

        # End of period: aging and old-age death, replacement, then the environment.
        for agent in list(self.agents):
            agent.age += 1
            if agent.age >= agent.max_age:
                self.kill(agent)
        if cfg.replacement:
            for _ in range(self.deaths_this_step):
                self.spawn_random_agent()

        if cfg.seasons is not None:
            beta, gamma = cfg.seasons
            self.landscape.seasonal_growback(self.t, cfg.growback_rate, beta, gamma, cfg.winter_growback)
        else:
            self.landscape.growback(cfg.growback_rate)
        if (
            cfg.diffusion_period is not None
            and self.t >= cfg.diffusion_start
            and self.t % cfg.diffusion_period == 0
        ):
            self.landscape.diffuse()
        self.t += 1

    def run(self, steps: int, observer: Callable[["Model"], None] | None = None) -> None:
        if observer:
            observer(self)
        for _ in range(steps):
            self.step()
            if observer:
                observer(self)

    # --- setup ---------------------------------------------------------------------------

    def _place_initial_population(self) -> None:
        cfg = self.config
        if cfg.placement == "block":
            x0, y0, w, h = cfg.block
            sites = [self.landscape.wrap(x0 + i, y0 + j) for i in range(w) for j in range(h)]
        else:
            sites = [(x, y) for x in range(cfg.width) for y in range(cfg.height)]
        if cfg.initial_population > len(sites):
            raise ValueError(
                f"{cfg.initial_population} agents do not fit in {len(sites)} {cfg.placement} sites"
            )
        for i in self.rng.choice(len(sites), size=cfg.initial_population, replace=False):
            self._spawn_at(*sites[int(i)])

    def _draw(self, bounds: tuple[int, int]) -> int:
        return int(self.rng.integers(bounds[0], bounds[1], endpoint=True))

    def _spawn_at(self, x: int, y: int) -> Agent:
        cfg = self.config
        vision = self._draw(cfg.vision)
        metabolism = self._draw(cfg.metabolism)
        sugar = self._draw(cfg.endowment)
        max_age = self._draw(cfg.max_age) if cfg.max_age is not None else math.inf
        return self.new_agent(x, y, vision, metabolism, sugar, max_age)
