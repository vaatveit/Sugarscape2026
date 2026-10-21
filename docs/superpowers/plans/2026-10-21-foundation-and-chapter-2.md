# Sugarscape Foundation + Chapter II Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Sugarscape core (config, landscape, agents, scheduler, movement, pollution, replacement, statistics, experiment runner, replication report) and reproduce every Chapter II result of *Growing Artificial Societies*.

**Architecture:** A pure-Python package `sugarscape/` holds one `Model` whose `step()` applies the enabled rules in the fixed order from the design. Experiments are named after book figures in `experiments/`; `replication/` compares their output to book targets and writes `results/REPORT.md`. Later chapters (III–VI) get their own plans and extend these same modules.

**Tech Stack:** Python 3.14 (project `.venv`), NumPy 2.x, matplotlib, pytest.

**Spec:** `docs/superpowers/specs/2026-10-21-sugarscape-design.md`, with rules and target numbers in `docs/book-notes.md`. Read both.

## Global Constraints

- Python ≥ 3.12; run everything through `.venv/Scripts/python` (Windows).
- One seeded `numpy.random.Generator` per model (`np.random.default_rng(config.seed)`), passed everywhere; never use the `random` module or global NumPy state.
- Coordinates: arrays indexed `[x, y]`; x grows east, y grows north; `y = 0` is the southern row. The lattice is a torus.
- Holdings and site levels are `float`; capacities, vision, metabolism, ages are `int`.
- Every rule function's docstring cites its book page; every interpretive choice is a `Config` field with a comment naming the ambiguity.
- Never tune a parameter away from the book's stated value to make a target pass. A failing target is investigated (superpowers:systematic-debugging), not loosened.
- Commit steps need the user's go-ahead (standing instruction); ask once at the first commit whether to commit after each task.
- Before writing code against NumPy, matplotlib, or pytest, check current docs with Context7 (standing instruction).

## Review Focus

1. **Extinction.** Population 0: `gini`, means, and neighbor stats must return `nan`, not raise; the step loop keeps running. Test in Task 6.
2. **Full lattice.** Placing more agents than empty sites (initial placement, block placement, replacement) raises `ValueError` with a clear message; `random_empty_site` returns `None` when full. Test in Task 4.
3. **Vision that wraps.** With vision ≥ half the grid, opposite scans would see the same sites twice. `Config` rejects `vision[1] * 2 >= min(width, height)`. Test in Task 1.
4. **Determinism.** The same experiment and seed produce byte-identical CSVs, including when run in worker processes. Test in Task 7.
5. **Bad ranges.** Any `(low, high)` range with `low > high` raises `ValueError` from `Config`. Test in Task 1.

---

## File Structure

```
pyproject.toml                  # package metadata, deps, pytest config (slow marker)
.gitignore                      # .venv/, results/, __pycache__/, *.egg-info
sugarscape/
  __init__.py
  config.py                     # Config dataclass + validation
  maps/__init__.py              # load_map(name) -> np.ndarray
  maps/sugar-map.txt            # 50x50 capacity data
  landscape.py                  # Landscape: levels, capacity, pollution, growback, seasons, diffusion
  agent.py                      # Agent dataclass
  model.py                      # Model: placement, occupancy, step() scheduler, death, replacement
  rules/__init__.py
  rules/movement.py             # M (with s/(1+p) score), harvest, metabolize
  stats.py                      # gini, lorenz, histogram, safe means, standard_metrics
experiments/
  __init__.py
  registry.py                   # Experiment dataclass, EXPERIMENTS dict, chapter II entries
  run.py                        # run_experiment, CLI, plotting
replication/
  __init__.py
  targets.py                    # Target dataclass, statistic helpers, chapter II targets
  report.py                     # evaluate, write_report, CLI
tests/
  conftest.py                   # tiny_model, put_agent helpers
  test_config.py  test_maps.py  test_landscape.py  test_model.py
  test_movement.py  test_stats.py  test_runner.py  test_report.py
  test_replication_ch2.py       # slow
```

---

### Task 1: Project skeleton and Config

**Files:**
- Create: `pyproject.toml`, `.gitignore`, `sugarscape/__init__.py`, `sugarscape/config.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Produces: `Config` (frozen dataclass) with exactly these fields and defaults:

```python
width: int = 50
height: int = 50
sugar_map: str = "sugar-map.txt"
initial_population: int = 400
placement: str = "random"                     # "random" | "block"
block: tuple[int, int, int, int] = (0, 0, 20, 20)   # x0, y0, w, h; II-6 block is our call
vision: tuple[int, int] = (1, 6)              # inclusive uniform integer range (p.24)
metabolism: tuple[int, int] = (1, 4)          # (p.24)
endowment: tuple[int, int] = (5, 25)          # (p.33); Ch II runs II-1/II-2 don't state it
max_age: tuple[int, int] | None = None        # None = immortal unless starving
replacement: bool = False                     # R[a,b]; requires max_age
growback_rate: float = 1.0                    # alpha in G_alpha; math.inf = G_inf
seasons: tuple[int, int] | None = None        # (beta, gamma) of S_alpha,beta,gamma
pollution: tuple[float, float] | None = None  # (alpha, beta) of P_alpha,beta
pollution_start: int = 0
diffusion_period: int | None = None           # alpha of D_alpha
diffusion_start: int = 0
seed: int = 0
```

- [ ] **Step 1: Create the venv and project files**

`pyproject.toml`: name `sugarscape`, `requires-python = ">=3.12"`, dependencies `numpy`, `matplotlib`; optional `dev = ["pytest"]`; setuptools package discovery including `sugarscape*`, `experiments*`, `replication*`, and package data `sugarscape/maps/*.txt`. Pytest config:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra --strict-markers -m 'not slow'"
markers = ["slow: replication runs (select with -m slow)"]
```

Run: `git init && python -m venv .venv && .venv/Scripts/python -m pip install -e ".[dev]"`
Expected: install succeeds.

- [ ] **Step 2: Write the failing tests**

```python
def test_defaults_match_chapter_two():
    c = Config()
    assert (c.width, c.height, c.initial_population) == (50, 50, 400)
    assert c.vision == (1, 6) and c.metabolism == (1, 4)

@pytest.mark.parametrize("field", ["vision", "metabolism", "endowment", "max_age"])
def test_inverted_range_rejected(field):
    with pytest.raises(ValueError):
        Config(**{field: (5, 2)})

def test_vision_that_wraps_rejected():
    with pytest.raises(ValueError):
        Config(vision=(1, 25))          # 25 * 2 >= 50
    Config(vision=(1, 20))              # Fig II-5 uses up to 20

def test_replacement_requires_max_age():
    with pytest.raises(ValueError):
        Config(replacement=True)

def test_config_is_frozen():
    with pytest.raises(dataclasses.FrozenInstanceError):
        Config().seed = 3
```

- [ ] **Step 3: Run to verify failure**

Run: `.venv/Scripts/python -m pytest tests/test_config.py -v`
Expected: FAIL (ImportError: `sugarscape.config`).

- [ ] **Step 4: Implement `Config` in `sugarscape/config.py`** with `__post_init__` validation (inverted ranges, wrapping vision, replacement without max_age, placement not in {"random","block"}).

- [ ] **Step 5: Run to verify pass**

Run: `.venv/Scripts/python -m pytest tests/test_config.py -v`
Expected: all PASS.

- [ ] **Step 6: Commit** (`.gitignore` excludes `.venv/`, `results/`, `__pycache__/`, `*.egg-info/`)

```bash
git add pyproject.toml .gitignore sugarscape tests docs
git commit -m "feat: project skeleton and validated Config"
```

---

### Task 2: Sugar capacity map

**Files:**
- Create: `sugarscape/maps/__init__.py`, `sugarscape/maps/sugar-map.txt`
- Test: `tests/test_maps.py`

**Interfaces:**
- Produces: `load_map(name: str) -> np.ndarray` returning an `int` array of shape `(width, height)` indexed `[x, y]`. File format: whitespace-separated integers, one text line per row, **first line = northernmost row** (so line `i` becomes `y = height - 1 - i`).

- [ ] **Step 1: Get the user's OK, then download the map into a fresh scratch folder**

Ask the user before downloading. Source: the 50×50 `sugar-map.txt` used by the NetLogo Sugarscape models in the `NetLogo/models` GitHub repository (Sample Models › Social Science › (unverified) Sugarscape). Confirm the exact path at execution time. Download into a new empty scratch directory, inspect it (50 lines, 50 integers each, values 0–4), then copy it into `sugarscape/maps/`. If no trustworthy source exists, stop and report back; the fallback (hand reconstruction from Figure II-1) needs the user's decision.

- [ ] **Step 2: Write the failing tests**

```python
def test_shape_and_range():
    m = load_map("sugar-map.txt")
    assert m.shape == (50, 50)
    assert m.min() == 0 and m.max() == 4

def test_peaks_are_northeast_and_southwest():   # Fig II-1, p.21
    m = load_map("sugar-map.txt")
    xs, ys = np.nonzero(m == 4)
    ne = (xs >= 25) & (ys >= 25)
    sw = (xs < 25) & (ys < 25)
    assert ne.any() and sw.any()
    assert (ne | sw).all()          # no level-4 cells in NW or SE
```

A vertically mirrored load would put the peaks NW/SE, so this test pins orientation.

- [ ] **Step 3: Run to verify failure.** Run: `.venv/Scripts/python -m pytest tests/test_maps.py -v`. Expected: FAIL (import error).

- [ ] **Step 4: Implement `load_map`** using `importlib.resources` to read the packaged file.

- [ ] **Step 5: Run to verify pass**, then render the map with matplotlib (`imshow(m.T, origin="lower")`) to a scratch PNG and compare by eye with Figure II-1 (two terraced circular peaks). Note the comparison in the commit message.

- [ ] **Step 6: Commit** — `git commit -m "feat: sugar capacity map with orientation tests"`

---

### Task 3: Landscape (growback, seasons, diffusion)

**Files:**
- Create: `sugarscape/landscape.py`
- Test: `tests/test_landscape.py`

**Interfaces:**
- Consumes: `Config`, `load_map`.
- Produces:

```python
class Landscape:
    capacity: np.ndarray      # int,   [x, y]
    sugar: np.ndarray         # float, starts equal to capacity (p.21)
    pollution: np.ndarray     # float, starts 0
    width: int; height: int
    def __init__(self, capacity: np.ndarray) -> None
    def wrap(self, x: int, y: int) -> tuple[int, int]
    def growback(self, rate: float) -> None                       # G_alpha (p.23)
    def seasonal_growback(self, t: int, alpha: float, beta: int, gamma: int) -> None   # S (p.44)
    def diffuse(self) -> None                                     # D (p.48)
    def is_summer_north(self, t: int, gamma: int) -> bool
```

Season rule (p.44 fn 33): north half (`y >= height // 2`) is in summer when `(t % (2*gamma)) < gamma`; the south half is the opposite. Summer sites add `alpha`; winter sites add `alpha` only on periods where `t % beta == 0` (our literal reading of "α units per β time intervals"; documented in the docstring). Diffusion replaces each site's pollution with the mean of its 4 von Neumann neighbors' **old** values (synchronous, torus).

- [ ] **Step 1: Write the failing tests**

```python
def test_growback_caps_at_capacity():
    ls = Landscape(np.array([[4, 2]]))
    ls.sugar[:] = [[0.0, 1.5]]
    ls.growback(1.0)
    assert ls.sugar.tolist() == [[1.0, 2.0]]

def test_g_infinity_refills_immediately():
    ls = Landscape(np.array([[4, 3]])); ls.sugar[:] = 0
    ls.growback(math.inf)
    assert ls.sugar.tolist() == [[4.0, 3.0]]

def test_seasons_flip_every_gamma():
    ls = Landscape(np.zeros((2, 2), dtype=int))
    assert ls.is_summer_north(0, 50) and ls.is_summer_north(49, 50)
    assert not ls.is_summer_north(50, 50) and ls.is_summer_north(100, 50)

def test_winter_grows_alpha_every_beta_periods():
    cap = np.full((1, 2), 4)                  # y=0 south, y=1 north
    ls = Landscape(cap); ls.sugar[:] = 0
    for t in range(8):                        # t=0..7, north summer
        ls.seasonal_growback(t, alpha=1, beta=8, gamma=50)
    assert ls.sugar[0, 1] == 4.0              # north: +1 per period, capped
    assert ls.sugar[0, 0] == 1.0              # south: +1 only at t=0

def test_diffusion_averages_von_neumann_neighbors_on_torus():
    ls = Landscape(np.zeros((3, 3), dtype=int))
    ls.pollution[1, 1] = 4.0
    ls.diffuse()
    assert ls.pollution[1, 1] == 0.0
    assert ls.pollution[0, 1] == ls.pollution[1, 0] == 1.0
    assert ls.pollution.sum() == pytest.approx(4.0)
```

- [ ] **Step 2: Run to verify failure.** `.venv/Scripts/python -m pytest tests/test_landscape.py -v` → FAIL (import).
- [ ] **Step 3: Implement `Landscape`** with NumPy array ops (`np.minimum`, `np.roll` for diffusion).
- [ ] **Step 4: Run to verify pass.** Same command → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: landscape growback, seasons, diffusion"`

---

### Task 4: Agents, Model, placement, scheduler skeleton, death, replacement

**Files:**
- Create: `sugarscape/agent.py`, `sugarscape/model.py`, `tests/conftest.py`
- Test: `tests/test_model.py`

**Interfaces:**
- Consumes: `Config`, `Landscape`, `load_map`.
- Produces:

```python
@dataclass(eq=False)
class Agent:
    id: int; x: int; y: int
    vision: int; metabolism: int
    sugar: float; initial_sugar: float
    max_age: float                 # math.inf when Config.max_age is None
    age: int = 0
    alive: bool = True
    moved: bool = False            # changed site this period (II-1 metric)
    neighbors: list["Agent"] = field(default_factory=list)   # post-move list (p.39)

class Model:
    config: Config; rng: np.random.Generator; landscape: Landscape
    t: int                         # periods completed
    agents: list[Agent]            # living agents, creation order
    deaths_this_step: int
    def __init__(self, config: Config, capacity: np.ndarray | None = None) -> None
    def agent_at(self, x: int, y: int) -> Agent | None
    def new_agent(self, x: int, y: int, vision: int, metabolism: int,
                  sugar: float, max_age: float = math.inf) -> Agent
    def spawn_random_agent(self) -> Agent          # random genetics/endowment/max_age at random empty site
    def random_empty_site(self) -> tuple[int, int] | None
    def move_agent(self, agent: Agent, x: int, y: int) -> None
    def kill(self, agent: Agent) -> None
    def step(self) -> None
    def run(self, steps: int, observer: Callable[["Model"], None] | None = None) -> None
```

`capacity` overrides the map (used by tests). `run` calls `observer(self)` once before the first step (t=0) and after each step.

`step()` order (design §Scheduling, Chapter II subset):
1. `order = [self.agents[i] for i in self.rng.permutation(len(self.agents))]`; reset `moved` and `deaths_this_step`.
2. For each agent in `order` that is still alive: `movement.move(self, agent)`, then `movement.metabolize(self, agent)`; if still alive, record `agent.neighbors` (living von Neumann neighbors now).
3. End of period: every living agent `age += 1`; kill those with `age >= max_age`; if `config.replacement`, call `spawn_random_agent()` once per death this period (starvation and old age); environment: `seasonal_growback` if `config.seasons` else `growback(config.growback_rate)`; if `config.diffusion_period` and `t >= diffusion_start` and `t % diffusion_period == 0`: `diffuse()`; `t += 1`.

Task 5 supplies `movement.move` and `movement.metabolize`; in this task use stubs in `sugarscape/rules/movement.py` that do nothing, so the scheduler is testable.

Initial placement: `"random"` = `initial_population` distinct random sites; `"block"` = distinct random sites inside the `block` rectangle. Agent genetics: `rng.integers(low, high, endpoint=True)` for vision, metabolism, endowment, max_age.

- [ ] **Step 1: Write `tests/conftest.py` helpers**

```python
def tiny_model(capacity, **overrides) -> Model:
    """Model on an explicit capacity grid with no initial agents."""
    base = dict(width=capacity.shape[0], height=capacity.shape[1],
                initial_population=0, vision=(1, 1))
    base.update(overrides)
    return Model(Config(**base), capacity=capacity)

def put_agent(model, x, y, vision=1, metabolism=1, sugar=10.0, max_age=math.inf) -> Agent:
    return model.new_agent(x, y, vision, metabolism, sugar, max_age)
```

(`tiny_model` callers that need larger vision pass `vision=(1, v)` and a grid with both sides greater than `2 * v`, or `Config` rejects it.)

- [ ] **Step 2: Write the failing tests**

```python
def test_random_placement_is_distinct_and_seeded():
    a, b = Model(Config(seed=7)), Model(Config(seed=7))
    pos = [(g.x, g.y) for g in a.agents]
    assert len(pos) == 400 == len(set(pos))
    assert pos == [(g.x, g.y) for g in b.agents]

def test_genetics_within_ranges():
    m = Model(Config(seed=1))
    assert {g.vision for g in m.agents} <= set(range(1, 7))
    assert {g.metabolism for g in m.agents} <= set(range(1, 5))
    assert all(5 <= g.sugar <= 25 and g.sugar == g.initial_sugar for g in m.agents)

def test_block_placement_inside_block():
    m = Model(Config(placement="block", block=(0, 0, 20, 20), initial_population=300))
    assert all(g.x < 20 and g.y < 20 for g in m.agents)

def test_overfull_placement_raises():
    with pytest.raises(ValueError):
        Model(Config(placement="block", block=(0, 0, 10, 10), initial_population=101))

def test_random_empty_site_none_when_full():
    m = tiny_model(np.ones((3, 3), dtype=int))
    for x in range(3):
        for y in range(3):
            put_agent(m, x, y)
    assert m.random_empty_site() is None

def test_old_age_death_and_replacement_keep_population_constant():
    m = Model(Config(initial_population=50, max_age=(1, 1), replacement=True, seed=3))
    m.step()
    assert len(m.agents) == 50 and all(g.age == 0 for g in m.agents)

def test_kill_frees_site():
    m = tiny_model(np.ones((3, 3), dtype=int))
    g = put_agent(m, 1, 1); m.kill(g)
    assert m.agent_at(1, 1) is None and not g.alive and g not in m.agents

def test_run_calls_observer_before_and_after_each_step():
    seen = []
    tiny_model(np.ones((3, 3), dtype=int)).run(3, observer=lambda m: seen.append(m.t))
    assert seen == [0, 1, 2, 3]
```

- [ ] **Step 3: Run to verify failure.** `.venv/Scripts/python -m pytest tests/test_model.py -v` → FAIL.
- [ ] **Step 4: Implement `Agent`, `Model`** (occupancy as a `width × height` list of lists of `Agent | None`).
- [ ] **Step 5: Run to verify pass.** Same command → PASS.
- [ ] **Step 6: Commit** — `git commit -m "feat: agents, model placement, scheduler, death and replacement"`

---

### Task 5: Movement M, harvesting, metabolism, pollution formation

**Files:**
- Modify: `sugarscape/rules/movement.py` (replace stubs)
- Test: `tests/test_movement.py`

**Interfaces:**
- Consumes: `Model.agent_at`, `Model.move_agent`, `Model.kill`, `Landscape` arrays.
- Produces:

```python
def site_score(model: Model, x: int, y: int) -> float      # sugar / (1 + pollution), p.47 fn 37
def candidate_sites(model: Model, agent: Agent) -> list[tuple[int, int, int]]
    # (x, y, distance): current site first at distance 0, then for each of the 4 directions
    # in an order from model.rng.permutation(4), distances 1..vision; unoccupied sites only
def move(model: Model, agent: Agent) -> None
def metabolize(model: Model, agent: Agent) -> None
```

Choice rule (p.25 and fn 8–9): highest score; among equal scores the smallest distance; among those the first in `candidate_sites` order. Using `sugar/(1+pollution)` always is equivalent to plain sugar while pollution is zero, so one rule covers M and "M modified for pollution".

`move`: relocate (set `agent.moved` if the site changed), add the site's sugar to `agent.sugar`, set the site's sugar to 0; if pollution is on (`config.pollution` set and `model.t >= pollution_start`), add `alpha * harvested` to that site's pollution (p.47).
`metabolize`: `agent.sugar -= agent.metabolism`; with pollution on, add `beta * metabolism` to the agent's site; if `agent.sugar <= 0`, `model.kill(agent)` (p.25).

- [ ] **Step 1: Write the failing tests** (grids built so only the tested feature decides)

```python
def line_model(levels, vision, **overrides):
    """Sugar row at y=1 starting at x=0; zero padding so west/south scans never wrap onto it."""
    n = len(levels) + 2 * vision + 2
    cap = np.zeros((n, n), dtype=int)
    cap[: len(levels), 1] = levels
    return tiny_model(cap, vision=(1, vision), **overrides)

def test_moves_to_max_sugar_within_vision():
    m = line_model([0, 1, 3, 2], vision=3); g = put_agent(m, 0, 1, vision=3)
    move(m, g); assert (g.x, g.y) == (2, 1) and g.sugar == 13.0
    assert m.landscape.sugar[2, 1] == 0.0

def test_cannot_see_beyond_vision():
    m = line_model([0, 1, 0, 0, 4], vision=2); g = put_agent(m, 0, 1, vision=2)
    move(m, g); assert g.x == 1

def test_no_diagonal_vision():
    cap = np.zeros((8, 8), dtype=int); cap[1, 1] = 4; cap[0, 3] = 1
    m = tiny_model(cap, vision=(1, 3)); g = put_agent(m, 0, 0, vision=3)
    move(m, g); assert (g.x, g.y) == (0, 3)

def test_skips_occupied_sites():
    m = line_model([0, 4, 2], vision=2); put_agent(m, 1, 1); g = put_agent(m, 0, 1, vision=2)
    move(m, g); assert g.x == 2

def test_nearest_wins_ties():
    m = line_model([0, 0, 3, 0, 3], vision=4); g = put_agent(m, 0, 1, vision=4)
    move(m, g); assert g.x == 2

def test_equal_distance_ties_are_random_direction():
    seen = set()
    for seed in range(20):
        cap = np.zeros((7, 7), dtype=int); cap[4, 3] = cap[2, 3] = 2
        m = tiny_model(cap, vision=(1, 1), seed=seed); g = put_agent(m, 3, 3)
        move(m, g); seen.add(g.x)
    assert seen == {2, 4}

def test_stays_when_current_site_is_best():
    m = line_model([4, 3], vision=1); g = put_agent(m, 0, 1)
    move(m, g); assert g.x == 0 and not g.moved and g.sugar == 14.0

def test_vision_wraps_around_torus():
    cap = np.zeros((6, 6), dtype=int); cap[5, 1] = 3      # one step west of x=0
    m = tiny_model(cap, vision=(1, 2)); g = put_agent(m, 0, 1, vision=2)
    move(m, g); assert g.x == 5

def test_starves_at_zero():
    m = line_model([0, 0], vision=1); g = put_agent(m, 0, 1, metabolism=2, sugar=2.0)
    move(m, g); metabolize(m, g); assert not g.alive and m.agent_at(0, 1) is None

def test_pollution_formation_and_avoidance():
    m = line_model([2, 3, 0], vision=1, pollution=(1.0, 1.0))
    m.landscape.pollution[1, 1] = 2.0     # score 3/3 = 1 < 2/1 at the current site
    g = put_agent(m, 0, 1, metabolism=1); move(m, g); metabolize(m, g)
    assert g.x == 0 and m.landscape.pollution[0, 1] == 2.0 + 1.0   # alpha*2 + beta*1
```

- [ ] **Step 2: Run to verify failure.** `.venv/Scripts/python -m pytest tests/test_movement.py -v` → FAIL.
- [ ] **Step 3: Implement** `site_score`, `candidate_sites`, `move`, `metabolize`.
- [ ] **Step 4: Run to verify pass.** Then the whole suite: `.venv/Scripts/python -m pytest -v` → PASS.
- [ ] **Step 5: Smoke run.** `.venv/Scripts/python -c "from sugarscape.model import Model; from sugarscape.config import Config; m=Model(Config(seed=1)); m.run(500); print(len(m.agents))"` → prints a number in roughly 200–250 (book: 224). A value far outside is a bug to investigate before continuing.
- [ ] **Step 6: Commit** — `git commit -m "feat: movement rule M with pollution scoring"`

---

### Task 6: Statistics

**Files:**
- Create: `sugarscape/stats.py`
- Test: `tests/test_stats.py`

**Interfaces:**
- Produces:

```python
def gini(values: Sequence[float]) -> float          # sum|xi-xj| / (2 n^2 mean); nan if empty or mean 0
def lorenz(values: Sequence[float]) -> tuple[np.ndarray, np.ndarray]   # population share, wealth share; both start at 0, end at 1
def histogram(values: Sequence[float], bins: int = 10) -> tuple[np.ndarray, np.ndarray]
def safe_mean(values: Sequence[float]) -> float     # nan if empty
def standard_metrics(model: Model) -> dict[str, float]
```

`standard_metrics` keys (all chapter II experiments record these every period):
`population`, `mean_vision`, `mean_metabolism`, `mean_sugar`, `gini`, `mean_neighbors`, `moved` (count of agents with `moved`), `ne_fraction` (share with `x >= w//2 and y >= h//2`), `on_peak_fraction` (share on sites with capacity ≥ 3), `north_frac_high_vision` (share of agents with vision ≥ 5 in the north half), `north_frac_low_vision` (same for vision ≤ 2), `summer_north` (1.0/0.0 from `landscape.is_summer_north(model.t, gamma)` when `config.seasons` is set, else `nan`).

- [ ] **Step 1: Write the failing tests**

```python
def test_gini_known_values():
    assert gini([5, 5, 5, 5]) == 0.0
    assert gini([0, 0, 0, 1]) == pytest.approx(0.75)
    assert gini(np.arange(5, 26)) == pytest.approx(20 / 90, abs=0.02)   # U[5,25] ≈ 0.23 (p.37)

def test_lorenz_endpoints_and_convexity():
    x, y = lorenz([1, 2, 3, 4])
    assert (x[0], y[0], x[-1], y[-1]) == (0, 0, 1, 1)
    assert np.all(y <= x + 1e-12)

def test_empty_population_gives_nan_not_error():
    assert math.isnan(gini([])) and math.isnan(safe_mean([]))
    m = tiny_model(np.ones((3, 3), dtype=int))
    out = standard_metrics(m)
    assert out["population"] == 0 and math.isnan(out["gini"])

def test_standard_metrics_keys():
    out = standard_metrics(Model(Config(seed=2)))
    assert set(out) == {"population", "mean_vision", "mean_metabolism", "mean_sugar", "gini",
                        "mean_neighbors", "moved", "ne_fraction", "on_peak_fraction",
                        "north_frac_high_vision", "north_frac_low_vision", "summer_north"}
```

- [ ] **Step 2: Run to verify failure.** `.venv/Scripts/python -m pytest tests/test_stats.py -v` → FAIL.
- [ ] **Step 3: Implement** the functions above.
- [ ] **Step 4: Run to verify pass.** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: Gini, Lorenz, and standard metrics"`

---

### Task 7: Experiment registry and runner

**Files:**
- Create: `experiments/__init__.py`, `experiments/registry.py`, `experiments/run.py`
- Test: `tests/test_runner.py`

**Interfaces:**
- Consumes: `Config`, `Model`, `standard_metrics`.
- Produces:

```python
@dataclass(frozen=True)
class Experiment:
    id: str            # book label, e.g. "II-4"; sweep points use "II-5/m2/v5.5"
    title: str
    rules: str         # book notation, e.g. "({G1}, {M})"
    config: Config     # seed field is the base seed
    steps: int
    seeds: int

EXPERIMENTS: dict[str, Experiment]
def register(exp: Experiment) -> Experiment

Series = list[dict[str, float]]   # one dict per t (0..steps), keys "t" + standard_metrics
def run_seed(exp_id: str, seed_index: int) -> Series          # config.seed = base + seed_index
def run_experiment(exp_id: str, seeds: int | None = None, jobs: int = 1,
                   out_dir: Path = Path("results")) -> list[Series]
    # writes results/<id with "/" -> "_">/seed<k>.csv and a PNG of population/gini/means over t
def load_results(exp_id: str, out_dir: Path = Path("results")) -> list[Series]
```

CLI: `python -m experiments.run <id-or-prefix> [--seeds N] [--jobs J]`; a prefix like `II-5` runs every matching id. Workers receive `(exp_id, seed_index)` and look the experiment up in `EXPERIMENTS` (keeps everything picklable on Windows). Chapter II entries are added in Task 9; this task registers one test experiment `"TEST-tiny"` (`initial_population=20`, 5 steps, 2 seeds).

- [ ] **Step 1: Write the failing tests**

```python
def test_same_seed_same_csv(tmp_path):
    run_experiment("TEST-tiny", out_dir=tmp_path / "a")
    run_experiment("TEST-tiny", out_dir=tmp_path / "b", jobs=2)
    for k in range(2):
        a = (tmp_path / "a" / "TEST-tiny" / f"seed{k}.csv").read_bytes()
        assert a == (tmp_path / "b" / "TEST-tiny" / f"seed{k}.csv").read_bytes()

def test_series_has_every_period(tmp_path):
    series = run_experiment("TEST-tiny", seeds=1, out_dir=tmp_path)[0]
    assert [row["t"] for row in series] == [0, 1, 2, 3, 4, 5]

def test_load_results_round_trips(tmp_path):
    out = run_experiment("TEST-tiny", out_dir=tmp_path)
    assert load_results("TEST-tiny", out_dir=tmp_path) == out
```

- [ ] **Step 2: Run to verify failure.** `.venv/Scripts/python -m pytest tests/test_runner.py -v` → FAIL.
- [ ] **Step 3: Implement** registry, `run_seed`, `run_experiment` (`concurrent.futures.ProcessPoolExecutor` when `jobs > 1`, results sorted by seed index), CSV via `csv.DictWriter` with `repr`-exact floats, matplotlib plot saved with the `Agg` backend.
- [ ] **Step 4: Run to verify pass.** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: experiment registry and deterministic runner"`

---

### Task 8: Replication targets and report

**Files:**
- Create: `replication/__init__.py`, `replication/targets.py`, `replication/report.py`
- Test: `tests/test_report.py`

**Interfaces:**
- Consumes: `run_experiment`, `load_results`, `Series`.
- Produces:

```python
@dataclass(frozen=True)
class Target:
    experiment: str
    name: str                               # e.g. "carrying capacity"
    book_value: float | None                # None for proxies of qualitative results
    low: float; high: float                 # pass band
    statistic: Callable[[Series], float]    # per-seed value
    source: str                             # e.g. "Fig II-4, p.31"
    proxy: bool = False                     # True when measuring a qualitative claim

def window_mean(metric: str, t0: int, t1: int) -> Callable[[Series], float]   # inclusive
def value_at(metric: str, t: int) -> Callable[[Series], float]
def ratio_of_windows(metric: str, a: tuple[int, int], b: tuple[int, int]) -> Callable[[Series], float]  # mean(a)/mean(b)
def seasonal_amplitude(metric: str, start: int, gamma: int, settle: int) -> Callable[[Series], float]
    # mean(metric | summer_north==1) - mean(metric | summer_north==0) over t >= start,
    # skipping the first `settle` periods after each flip

TARGETS: list[Target]

@dataclass(frozen=True)
class Result:
    target: Target; observed_mean: float; observed_min: float; observed_max: float
    status: str                             # "pass" | "near" | "fail"

def evaluate(target: Target, runs: list[Series]) -> Result
    # pass: low <= mean <= high; near: within the band widened by half its width on each side; else fail
def write_report(results: list[Result], path: Path) -> None
```

`write_report` writes a Markdown table: Experiment | Target | Source | Book | Band | Observed mean [min–max] | Status, with proxies marked "(proxy)". CLI: `python -m replication.report [--chapter II] [--rerun] [--jobs J]` runs any experiment lacking results (or all with `--rerun`), evaluates the chapter's targets, writes `results/REPORT.md`.

- [ ] **Step 1: Write the failing tests**

```python
SERIES = [{"t": t, "population": 400 - t, "summer_north": float(t < 5)} for t in range(10)]

def test_window_mean_and_value_at():
    assert window_mean("population", 8, 9)(SERIES) == 391.5
    assert value_at("population", 0)(SERIES) == 400

def test_seasonal_amplitude():
    s = [{"t": t, "x": 1.0 if t < 5 else 0.0, "summer_north": float(t < 5)} for t in range(10)]
    assert seasonal_amplitude("x", start=0, gamma=5, settle=0)(s) == 1.0

def test_evaluate_statuses():
    t = Target("X", "pop", 395, 390, 400, value_at("population", 5), "test")
    assert evaluate(t, [SERIES]).status == "pass"
    t2 = Target("X", "pop", 380, 380, 390, value_at("population", 5), "test")
    assert evaluate(t2, [SERIES]).status == "near"       # 395 within 390 + 5
    t3 = Target("X", "pop", 300, 300, 310, value_at("population", 5), "test")
    assert evaluate(t3, [SERIES]).status == "fail"

def test_report_lists_every_target(tmp_path):
    t = Target("X", "pop", 395, 390, 400, value_at("population", 5), "test", proxy=True)
    write_report([evaluate(t, [SERIES])], tmp_path / "R.md")
    text = (tmp_path / "R.md").read_text()
    assert "pop" in text and "pass" in text and "(proxy)" in text
```

- [ ] **Step 2: Run to verify failure.** `.venv/Scripts/python -m pytest tests/test_report.py -v` → FAIL.
- [ ] **Step 3: Implement** targets helpers, `evaluate`, `write_report`, CLI.
- [ ] **Step 4: Run to verify pass.** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: replication targets and report"`

---

### Task 9: Chapter II experiments and targets

**Files:**
- Modify: `experiments/registry.py` (register chapter II), `replication/targets.py` (append chapter II targets)
- Test: `tests/test_replication_ch2.py` (marked `slow`)

**Interfaces:**
- Consumes: everything above.
- Produces: the experiments and targets below. Base configs use `Config()` defaults unless listed.

| Id | Rules | Config differences | Steps | Seeds |
|---|---|---|---|---|
| `II-1` | ({G∞},{M}) | `growback_rate=math.inf` | 100 | 5 |
| `II-4` | ({G1},{M}) | — | 500 | 10 |
| `II-5/m{a}/v{b}` | ({G1},{M}) | `initial_population=500`, metabolism and vision ranges below | 500 | 10 |
| `II-4-gini` | ({G1},{M,R[60,100]}) | `initial_population=250`, `max_age=(60, 100)`, `replacement=True` | 500 | 10 |
| `II-6` | ({G1},{M}) | `vision=(1, 10)`, `placement="block"` | 300 | 5 |
| `II-7` | ({S1,8,50},{M}) | `seasons=(8, 50)` | 500 | 5 |
| `II-8` | ({G1, D1},{M, P11}) | `pollution=(1.0, 1.0)`, `pollution_start=50`, `diffusion_period=1`, `diffusion_start=100` | 200 | 5 |

Fig II-5 sweep (our call, since the book gives only means): a mean of `k` is a uniform range `(1, 2k - 1)`. Metabolism means 1, 2, 3 → `(1,1)`, `(1,3)`, `(1,5)`. Vision means 1, 2, 3, 5.5, 10.5 → `(1,1)`, `(1,3)`, `(1,5)`, `(1,10)`, `(1,20)`; for metabolism 3 also 4.5, 6.5, 8 → `(1,8)`, `(1,12)`, `(1,15)`. The animation II-6 block `(0, 0, 20, 20)` is also our call (Figure II-6 frame 1 shows roughly the SW 20×20).

Targets (bands are starting tolerances; widen only with recorded seed-spread evidence):

| Experiment | Name | Book | Band | Statistic | Source |
|---|---|---|---|---|---|
| II-1 | agents still moving (proxy) | — | 0–0.5 | `window_mean("moved", 80, 100)` | Anim II-1, p.28 |
| II-4 | carrying capacity | 224 | 205–245 | `window_mean("population", 450, 500)` | Fig II-4, p.31 |
| II-4 | mean vision at t=500 | 4.1 | 3.9–4.3 | `value_at("mean_vision", 500)` | p.32 |
| II-4 | mean metabolism at t=500 | 1.8 | 1.6–2.0 | `value_at("mean_metabolism", 500)` | p.32 |
| II-4 | mean neighbors | 0.9 | 0.75–1.05 | `window_mean("mean_neighbors", 100, 500)` | Anim II-5, p.41 |
| II-5/* | carrying capacity | Fig II-5 value | ±10% of it | `window_mean("population", 450, 500)` | Fig II-5, p.31 |
| II-4-gini | initial Gini | 0.230 | 0.20–0.26 | `value_at("gini", 0)` | Anim II-4, p.38 |
| II-4-gini | long-run Gini | 0.503 | 0.45–0.56 | `window_mean("gini", 300, 500)` | Anim II-4, p.37 |
| II-6 | wave reaches NE peak (proxy) | — | 0.15–1.0 | `value_at("ne_fraction", 200)` | Anim II-6, p.43 |
| II-7 | high-vision agents migrate (proxy) | — | 0.3–1.0 | `seasonal_amplitude("north_frac_high_vision", 100, 50, 10)` | Anim II-7, p.45 |
| II-7 | low-vision agents hibernate (proxy) | — | −0.15–0.15 | `seasonal_amplitude("north_frac_low_vision", 100, 50, 10)` | Anim II-7, p.45 |
| II-8 | peaks abandoned under pollution (proxy) | — | 0–0.6 | `ratio_of_windows("on_peak_fraction", (90, 100), (40, 50))` | Anim II-8, p.48 |
| II-8 | lower carrying capacity when polluted (proxy) | — | 0–0.9 | `ratio_of_windows("population", (95, 100), (45, 50))` | p.50 |

Fig II-5 book values (from `book-notes.md`): ⟨m⟩=1: 450, 465, 475, 490, 495 at v 1, 2, 3, 5.5, 10.5; ⟨m⟩=2: 330, 365, 375, 390, 400; ⟨m⟩=3: 225, 228, 255, 260, 260, 287, 280, 287 at v 1, 2, 3, 4.5, 5.5, 6.5, 8, 10.5.

- [ ] **Step 1: Write the slow replication test**

```python
@pytest.mark.slow
@pytest.mark.parametrize("target", [t for t in TARGETS if t.experiment.startswith("II-")],
                         ids=lambda t: f"{t.experiment}:{t.name}")
def test_chapter2_target(target):
    runs = load_or_run(target.experiment)
    result = evaluate(target, runs)
    assert result.status == "pass", result
```

Define `load_or_run(exp_id)` in the same test file: return `load_results(exp_id)` when `results/<id>/` has every seed's CSV, else `run_experiment(exp_id)`.

- [ ] **Step 2: Register the experiments and targets** listed above.
- [ ] **Step 3: Fast check.** `.venv/Scripts/python -m pytest -v` (slow tests deselected) → PASS; `.venv/Scripts/python -m experiments.run II-4 --seeds 1` writes `results/II-4/seed0.csv` and a PNG.
- [ ] **Step 4: Full Chapter II replication** (run in the background; the II-5 sweep is 18 points × 10 seeds).

Run: `.venv/Scripts/python -m replication.report --chapter II --jobs 8`
Then: `.venv/Scripts/python -m pytest -m slow -v`
Expected: `results/REPORT.md` lists every Chapter II target. Each `fail` or `near` goes through superpowers:systematic-debugging against the book text before anything changes; a rule fix gets its own unit test first. Bands are not widened to make a target pass.

- [ ] **Step 5: Visual check against the book.** Render population snapshots for II-1, II-4, II-6, II-7, II-8 at a few times (scratch script; matplotlib scatter over the capacity map) and compare by eye with Animations II-1, II-2, II-6, II-7, II-8. Record the observations in `results/REPORT.md` under "Visual comparison".
- [ ] **Step 6: Commit** — `git commit -m "feat: chapter II experiments and replication targets"` (the `results/` folder stays untracked; REPORT.md is copied to `docs/replication/chapter-2.md` and committed).

---

## Later plans (not part of this plan)

One plan each, written after the previous one lands: Chapter III (S, I, K, friends, genealogy, C_α, proto-history), Chapter IV (spice, welfare, T, price statistics, culturally varying preferences, pollution and prices, foresight, L_dr), Chapter V (E), Chapter VI (all-rules run, indecomposability, Schelling, Ring World), and the viewer.
