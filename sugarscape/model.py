"""The model: agents on a landscape, advanced one period at a time by `step()`."""

import math
from collections.abc import Callable, Collection

import numpy as np

from sugarscape.agent import Agent
from sugarscape.config import Config
from sugarscape.landscape import Landscape
from sugarscape.maps import load_map
from sugarscape.rules import combat, credit, culture, movement, sex, trade
from sugarscape.rules.culture import random_tags

VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))


class Model:
    def __init__(self, config: Config, capacity: np.ndarray | None = None) -> None:
        self.config = config
        self.rng = np.random.default_rng(config.seed)
        if capacity is None:
            capacity = load_map(config.sugar_map)
        if capacity.shape != (config.width, config.height):
            raise ValueError(f"capacity shape {capacity.shape} != ({config.width}, {config.height})")
        # Fig IV-1: spice mountains NW and SE, i.e. the sugar map mirrored east-west.
        self.landscape = Landscape(capacity, capacity[::-1, :] if config.spice else None)
        self._grid: list[list[Agent | None]] = [[None] * config.height for _ in range(config.width)]
        self.agents: list[Agent] = []
        self.t = 0
        self.dead_this_step: list[Agent] = []
        self.trade_log: list[trade.Exchange] = []  # this period's exchanges (rule T)
        self.loans: list[credit.Loan] = []  # active loans (rule L)
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

    def spawn_random_agent(self, tribe: str | None = None) -> Agent:
        """A new agent with random genetics, endowment, and max age at a random empty site (R, p.32).

        With a tribe, its random tags are drawn to belong to that tribe (same-tribe R, p.86).
        """
        site = self.random_empty_site()
        if site is None:
            raise ValueError("no empty site for a new agent: the lattice is full")
        return self._spawn_at(*site, tribe=tribe)

    def move_agent(self, agent: Agent, x: int, y: int) -> None:
        x, y = self.landscape.wrap(x, y)
        if (x, y) == (agent.x, agent.y):
            return
        if self._grid[x][y] is not None:
            raise ValueError(f"site ({x}, {y}) is occupied")
        self._grid[agent.x][agent.y] = None
        self._grid[x][y] = agent
        w, h = self.config.width, self.config.height
        agent.disp_x += (x - agent.x + w // 2) % w - w // 2  # shortest way round the torus
        agent.disp_y += (y - agent.y + h // 2) % h - h // 2
        agent.x, agent.y = x, y

    def kill(self, agent: Agent) -> None:
        agent.alive = False
        self._grid[agent.x][agent.y] = None
        self.agents.remove(agent)
        self.dead_this_step.append(agent)

    @property
    def deaths_this_step(self) -> int:
        return len(self.dead_this_step)

    def die(self, agent: Agent, excluded_heirs: Collection[Agent] = ()) -> None:
        """Every death goes through here: inheritance I (p.67) when enabled, then removal.

        The positive part of the agent's wealth is split equally among its living children,
        skipping `excluded_heirs` (agents dying in the same batch; Kehoe's reading).
        """
        if self.loans:
            credit.on_death(self, agent, excluded_heirs)
        if self.config.inheritance:
            heirs = [c for c in agent.children if c.alive and c not in excluded_heirs]
            for heir in heirs:
                if agent.sugar > 0:
                    heir.sugar += agent.sugar / len(heirs)
                if agent.spice > 0:
                    heir.spice += agent.spice / len(heirs)
        self.kill(agent)

    # --- time ----------------------------------------------------------------------------

    def step(self) -> None:
        """One period, in the order fixed by the design (docs/superpowers/specs, Scheduling)."""
        cfg = self.config
        self.dead_this_step = []
        self.trade_log = []
        for agent in self.agents:
            agent.moved = False

        # Agents act one at a time in a fresh random order each period (p.26).
        order = [self.agents[i] for i in self.rng.permutation(len(self.agents))]
        for agent in order:
            if not agent.alive:
                continue
            if cfg.combat_alpha is not None:
                combat.combat_move(self, agent)
            else:
                movement.move(self, agent)
            movement.metabolize(self, agent)
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

        # End of period: aging and old-age death, replacement, then the environment.
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
        if cfg.initial_blocks:
            for tribe, x0, y0, w, h, n in cfg.initial_blocks:
                sites = [(x0 + i, y0 + j) for i in range(w) for j in range(h) if self._grid[x0 + i][y0 + j] is None]
                if n > len(sites):
                    raise ValueError(f"{n} {tribe} agents do not fit in {len(sites)} empty block sites")
                for i in self.rng.choice(len(sites), size=n, replace=False):
                    self._spawn_at(*sites[int(i)], tribe=tribe)
            return
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

    def _spawn_at(self, x: int, y: int, tribe: str | None = None) -> Agent:
        cfg = self.config
        vision = self._draw(cfg.vision)
        metabolism = self._draw(cfg.metabolism)
        sugar = self._draw(cfg.endowment)
        max_age = self._draw(cfg.max_age) if cfg.max_age is not None else math.inf
        agent = self.new_agent(x, y, vision, metabolism, sugar, max_age)
        # Chapter III draws come after the Chapter II ones so Chapter II streams are unchanged.
        if cfg.tag_length:
            agent.tags = random_tags(self.rng, cfg.tag_length, tribe)
        if cfg.sex:
            self._assign_sex(agent, "F" if self.rng.integers(2) == 0 else "M")
        # Chapter IV draws come last so earlier chapters' streams are unchanged.
        if cfg.spice:
            agent.spice_metabolism = self._draw(cfg.spice_metabolism)
            agent.spice = agent.initial_spice = float(self._draw(cfg.spice_endowment or cfg.endowment))
            if cfg.foresight is not None:
                agent.foresight = self._draw(cfg.foresight)
        return agent

    def _assign_sex(self, agent: Agent, sex: str) -> None:
        """Sex and childbearing ages, each a random value in the stated range (p.57 fn 4)."""
        cfg = self.config
        agent.sex = sex
        agent.fertility_start = self._draw(cfg.fertility_start)
        agent.fertility_end = self._draw(cfg.female_fertility_end if sex == "F" else cfg.male_fertility_end)
