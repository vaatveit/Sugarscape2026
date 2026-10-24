"""Cross-language scenarios: small states whose outcome cannot depend on the agents' order or the random draws.

Usage (from julia/): python -m bridge.scenarios
Each scenario runs through the Python model; its inputs and end state go to julia/test/fixtures/scenarios.toml, which
the Julia tests replay with no Python at test time. A scenario whose end state differs between seeds 0, 1 and 2
depends on order or draws, so it is refused (as flamegpu/tests/test_parity.py checks its own).
"""

import math
import random
from dataclasses import dataclass, field

import numpy as np

from bridge.export_registry import _string, _value
from bridge.paths import JULIA_DIR
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.trade import bargain

FIXTURES = JULIA_DIR / "test" / "fixtures" / "scenarios.toml"
SEEDS = (0, 1, 2)
CONSTRUCTOR = ("x", "y", "vision", "metabolism", "sugar", "max_age")


@dataclass(frozen=True)
class Scenario:
    config: dict  # Config overrides on top of Config(width=W, height=H, initial_population=0)
    capacity: list[list[int]]  # [x][y]
    agents: list[dict]  # x, y, vision, metabolism, sugar; optionally any Agent field, tags as 0/1 lists, children
    steps: int
    # Rules applied directly before the steps, as (rule, agent index, ...): ("bargain", i, j) runs rule T between
    # agents i and j. For rules whose outcome over a whole period would depend on who acts first.
    actions: tuple = ()
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


def _grid(n: int, sites: dict[tuple[int, int], int] | None = None) -> list[list[int]]:
    cap = [[0] * n for _ in range(n)]
    for (x, y), v in (sites or {}).items():
        cap[x][y] = v
    return cap


# Chapter III. Bystanders have vision 0 and metabolism 0, so they neither move nor change, whatever the order.
_COMBAT = {"tag_length": 1, "combat_alpha": math.inf, "vision": (1, 4)}
SCENARIOS.update({
    "combat_takes_weaker_enemy": Scenario(_COMBAT, _grid(12), [
        {"x": 1, "y": 1, "vision": 4, "metabolism": 1, "sugar": 20.0, "tags": [0]},
        {"x": 3, "y": 1, "vision": 0, "metabolism": 0, "sugar": 8.0, "tags": [1]}], 2),
    "combat_alpha_caps_the_take": Scenario({**_COMBAT, "combat_alpha": 2.0}, _grid(12), [
        {"x": 1, "y": 1, "vision": 4, "metabolism": 1, "sugar": 20.0, "tags": [0]},
        {"x": 3, "y": 1, "vision": 0, "metabolism": 0, "sugar": 8.0, "tags": [1]}], 2),
    # The target (3, 1) is vulnerable (30 > 20 + 8) and so is the agent's own site; (1, 3) is the one safe reward.
    "combat_retaliation_blocks": Scenario(_COMBAT, _grid(12, {(1, 3): 3}), [
        {"x": 1, "y": 1, "vision": 4, "metabolism": 1, "sugar": 20.0, "tags": [0]},
        {"x": 3, "y": 1, "vision": 0, "metabolism": 0, "sugar": 8.0, "tags": [1]},
        {"x": 5, "y": 1, "vision": 0, "metabolism": 0, "sugar": 30.0, "tags": [1]}], 2),
    # The parent and one child die of age in the same batch; the other child inherits everything (p.67).
    "inheritance_to_child": Scenario({"inheritance": True, "max_age": (1, 100), "vision": (1, 1)}, _grid(5), [
        {"x": 0, "y": 0, "vision": 1, "metabolism": 1, "sugar": 40.0, "max_age": 1, "children": [1, 2]},
        {"x": 2, "y": 2, "vision": 1, "metabolism": 1, "sugar": 10.0, "max_age": 1},
        {"x": 4, "y": 4, "vision": 1, "metabolism": 1, "sugar": 10.0}], 1),
})



def _pairs(n: int, seed: int, tags: int = 0) -> tuple[list[dict], tuple]:
    """n trading pairs with fixed random holdings and metabolisms, for rule T applied directly."""
    rng = random.Random(seed)
    agents = []
    for k in range(2 * n):
        a = {"x": k % 10, "y": k // 10, "vision": 1, "metabolism": rng.randint(1, 5),
             "sugar": round(rng.uniform(1, 100), 3), "spice": round(rng.uniform(1, 100), 3),
             "spice_metabolism": rng.randint(1, 5)}
        if tags:
            a["tags"] = [rng.randint(0, 1) for _ in range(tags)]
        agents.append(a)
    return agents, tuple(("bargain", 2 * i, 2 * i + 1) for i in range(n))


# Chapter IV. Trading neighbours are not order-free over a period (each metabolizes before trading), so rule T is
# applied directly to fixed pairs; movement on the sugar-and-spice landscape uses the four far-apart agents.
_TRADE = {"spice": True, "trade": True, "vision": (1, 1)}
_PAIRS, _BARGAINS = _pairs(15, 11)
_CPAIRS, _CBARGAINS = _pairs(15, 12, tags=3)
SCENARIOS.update({
    "trade_pairs": Scenario(_TRADE, _grid(10), _PAIRS, 0, _BARGAINS),
    "trade_pairs_whole_units": Scenario({**_TRADE, "trade_rounding": "down"}, _grid(10), _PAIRS, 0, _BARGAINS),
    "trade_pairs_cultural": Scenario({**_TRADE, "tag_length": 3, "cultural_preferences": True}, _grid(10),
                                     _CPAIRS, 0, _CBARGAINS),
    "spice_move": Scenario({"spice": True}, DISTINCT, _four(spice=30.0, spice_metabolism=2), 4),
    "spice_move_foresight": Scenario({"spice": True, "foresight": (0, 10)}, DISTINCT,
                                     _four(spice=30.0, spice_metabolism=2, foresight=5), 4),
    "spice_move_polluted": Scenario({"spice": True, "pollution": (1.0, 1.0), "diffusion_period": 1}, DISTINCT,
                                    _four(spice=30.0, spice_metabolism=2), 4),
    # A lender past childbearing (metabolism 0, so its wealth is the same whoever acts first) and a fertile
    # borrower short of its endowment, both female so no child is born; the loan falls due at t = 10 and is repaid.
    "credit_loan_and_repayment": Scenario({"sex": True, "credit": (10, 10.0), "vision": (1, 1)},
                                          _grid(7, {(3, 4): 10}), [
        {"x": 3, "y": 3, "vision": 1, "metabolism": 0, "sugar": 100.0, "age": 50, "sex": "F",
         "fertility_start": 12, "fertility_end": 40, "initial_sugar": 60.0},
        {"x": 3, "y": 4, "vision": 1, "metabolism": 0, "sugar": 20.0, "age": 20, "sex": "F",
         "fertility_start": 12, "fertility_end": 40, "initial_sugar": 60.0}], 12),
})

def build(sc: Scenario, seed: int) -> tuple[Model, list]:
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
    return m, agents


def run_scenario(sc: Scenario, seed: int) -> dict:
    """The end state: living agents by id (x, y, sugar, spice, age) and the sugar, spice and pollution grids."""
    m, agents = build(sc, seed)
    for rule, *who in sc.actions:
        if rule != "bargain":
            raise ValueError(f"unknown scenario action {rule!r}")
        m.trade_log.extend(bargain(m, agents[who[0]], agents[who[1]]))
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
                f"actions = {_toml([list(a) for a in sc.actions])}",
                f"expected = {_inline(state)}", ""]
    return "\n".join(out)


def main() -> None:
    FIXTURES.parent.mkdir(parents=True, exist_ok=True)
    FIXTURES.write_text(fixture_text(), encoding="utf-8", newline="\n")
    print(f"wrote {FIXTURES}: {len(SCENARIOS)} scenarios")


if __name__ == "__main__":
    main()
