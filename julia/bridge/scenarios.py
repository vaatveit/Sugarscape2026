"""Cross-language scenarios: small states whose outcome cannot depend on the agents' order or the random draws.

Usage (from julia/): python -m bridge.scenarios
Each scenario runs through the Python model; its inputs and end state go to julia/test/fixtures/scenarios.toml, which
the Julia tests replay with no Python at test time. A scenario whose end state differs between seeds 0, 1 and 2
depends on order or draws, so it is refused (as flamegpu/tests/test_parity.py checks its own).
"""

import math
from dataclasses import dataclass, field

import numpy as np

from bridge.export_registry import _string, _value
from bridge.paths import JULIA_DIR
from sugarscape.config import Config
from sugarscape.model import Model

FIXTURES = JULIA_DIR / "test" / "fixtures" / "scenarios.toml"
SEEDS = (0, 1, 2)
CONSTRUCTOR = ("x", "y", "vision", "metabolism", "sugar", "max_age")


@dataclass(frozen=True)
class Scenario:
    config: dict  # Config overrides on top of Config(width=W, height=H, initial_population=0)
    capacity: list[list[int]]  # [x][y]
    agents: list[dict]  # x, y, vision, metabolism, sugar; optionally any Agent field, tags as 0/1 lists, children
    steps: int
    notes: str = field(default="")


# Every capacity distinct, so no two candidate sites tie (flamegpu/tests/test_parity.py).
DISTINCT = ((np.random.default_rng(1).permutation(400) + 2).reshape(20, 20)).tolist()


def _four(visions=(1, 2, 3, 3), metabolisms=(1, 2, 3, 4), sugar=10.0, **extra) -> list[dict]:
    """Four agents ten sites apart: farther than any of them sees, so the order they act in cannot matter."""
    sites = ((2, 2), (12, 2), (2, 12), (12, 12))
    return [{"x": x, "y": y, "vision": v, "metabolism": m, "sugar": sugar, **extra}
            for (x, y), v, m in zip(sites, visions, metabolisms)]


SCENARIOS: dict[str, Scenario] = {
    "g1_move": Scenario({}, DISTINCT, _four(), 3),
    "g_inf": Scenario({"growback_rate": math.inf}, DISTINCT, _four(), 5),
    "wrap_max_vision": Scenario({"growback_rate": math.inf, "vision": (1, 9)}, DISTINCT,
                                [{"x": 0, "y": 19, "vision": 9, "metabolism": 2, "sugar": 10.0}], 3),
    "starvation": Scenario({}, DISTINCT, _four(metabolisms=(500, 500, 500, 500), sugar=1.0), 2),
    "max_age_death": Scenario({"max_age": (2, 2)}, DISTINCT, _four(max_age=2), 3),
    "seasons_fractional": Scenario({"seasons": (4, 3), "winter_growback": "fractional"}, DISTINCT, _four(), 7),
    "seasons_pulse": Scenario({"seasons": (4, 3), "winter_growback": "pulse"}, DISTINCT, _four(), 7),
    "pollution": Scenario({"pollution": (1.0, 1.0), "pollution_start": 1, "pollution_stop": 3}, DISTINCT,
                          _four(), 5),
    "pollution_diffusion": Scenario({"pollution": (1.0, 1.0), "diffusion_period": 2, "diffusion_start": 1},
                                    DISTINCT, _four(), 6),
    "pollution_diffusion_3_passes": Scenario({"pollution": (1.0, 1.0), "diffusion_period": 1, "diffusion_start": 1,
                                              "diffusion_passes": 3}, DISTINCT, _four(), 4),
}


def build(sc: Scenario, seed: int) -> Model:
    width, height = len(sc.capacity), len(sc.capacity[0])
    cfg = Config(width=width, height=height, initial_population=0, seed=seed, **sc.config)
    m = Model(cfg, capacity=np.array(sc.capacity, dtype=int))
    agents = []
    for spec in sc.agents:
        a = m.new_agent(spec["x"], spec["y"], spec["vision"], spec["metabolism"], spec["sugar"],
                        spec.get("max_age", math.inf))
        for k, v in spec.items():
            if k not in CONSTRUCTOR and k != "children":
                setattr(a, k, list(v) if k == "tags" else v)
        agents.append(a)
    for spec, a in zip(sc.agents, agents):
        a.children = [agents[i] for i in spec.get("children", ())]
    return m


def run_scenario(sc: Scenario, seed: int) -> dict:
    """The end state: living agents by id (x, y, sugar, spice, age) and the sugar, spice and pollution grids."""
    m = build(sc, seed)
    m.run(sc.steps)
    ls = m.landscape
    return {"agents": [{"x": a.x, "y": a.y, "sugar": float(a.sugar), "spice": float(a.spice), "age": a.age}
                       for a in sorted(m.agents, key=lambda a: a.id)],
            "sugar": ls.sugar.tolist(), "spice": ls.spice.tolist(), "pollution": ls.pollution.tolist()}


def same_state(a: dict, b: dict) -> bool:
    if [(x["x"], x["y"], x["age"]) for x in a["agents"]] != [(x["x"], x["y"], x["age"]) for x in b["agents"]]:
        return False
    if not all(math.isclose(x[k], y[k], rel_tol=1e-12, abs_tol=1e-9)
               for x, y in zip(a["agents"], b["agents"]) for k in ("sugar", "spice")):
        return False
    return all(np.allclose(a[k], b[k], rtol=1e-12, atol=1e-9) for k in ("sugar", "spice", "pollution"))


def _inline(d: dict) -> str:
    return "{ " + ", ".join(f"{k} = {_toml(v)}" for k, v in d.items()) + " }"


def _toml(v) -> str:
    if isinstance(v, dict):
        return _inline(v)
    if isinstance(v, list):
        return "[" + ", ".join(_toml(x) for x in v) + "]"
    return _value(v)


def fixture_text() -> str:
    out = ["# Generated by `python -m bridge.scenarios` from the Python model. Do not edit.", ""]
    for name, sc in SCENARIOS.items():
        state = run_scenario(sc, SEEDS[0])
        for seed in SEEDS[1:]:
            if not same_state(run_scenario(sc, seed), state):
                raise ValueError(f"scenario {name} depends on the agents' order or the random draws")
        out += ["[[scenario]]", f"name = {_string(name)}", f"steps = {sc.steps}",
                f"width = {len(sc.capacity)}", f"height = {len(sc.capacity[0])}",
                f"config = {_inline(sc.config)}", f"capacity = {_toml(sc.capacity)}",
                f"agents = {_toml([dict(a) for a in sc.agents])}",
                f"expected = {_inline(state)}", ""]
    return "\n".join(out)


def main() -> None:
    FIXTURES.parent.mkdir(parents=True, exist_ok=True)
    FIXTURES.write_text(fixture_text(), encoding="utf-8", newline="\n")
    print(f"wrote {FIXTURES}: {len(SCENARIOS)} scenarios")


if __name__ == "__main__":
    main()
