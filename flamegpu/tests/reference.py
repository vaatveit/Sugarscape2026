"""The same scenario through the Python reference model (sugarscape.model.Model)."""

import math
from dataclasses import replace

import numpy as np

from bridge.paths import SUGARSCAPE_ROOT  # noqa: F401  (puts the Python project on sys.path)
from gpu import DEFAULT_CFG, Dump
from sugarscape.config import Config
from sugarscape.model import Model

RANGES = ("vision", "metabolism", "endowment", "max_age")


def config_from_cfg(cfg: dict) -> Config:
    """A Config from run.cfg-spelled values (DEFAULT_CFG plus cfg)."""
    values = {**DEFAULT_CFG, **cfg}
    kwargs = {}
    for key in ("width", "height", "initial_population", "pollution_start", "diffusion_start", "seed"):
        kwargs[key] = int(values[key])
    for key in ("pollution_stop", "diffusion_period"):
        kwargs[key] = int(values[key]) if values[key] else None
    for key in RANGES:
        kwargs[key] = tuple(int(v) for v in values[key].split(",")) if values[key] else None
    kwargs["block"] = tuple(int(v) for v in values["block"].split(","))
    kwargs["seasons"] = tuple(int(v) for v in values["seasons"].split(",")) if values["seasons"] else None
    kwargs["pollution"] = tuple(float(v) for v in values["pollution"].split(",")) if values["pollution"] else None
    kwargs["growback_rate"] = math.inf if values["growback_rate"] == "inf" else float(values["growback_rate"])
    kwargs["replacement"] = values["replacement"] == "true"
    kwargs["diffusion_passes"] = int(values.get("diffusion_passes", "1"))
    for key in ("placement", "founder_ages", "winter_growback"):
        kwargs[key] = values[key]
    return Config(**kwargs)


def run_python(cfg: dict, capacity: np.ndarray, agents: list[dict], steps: int) -> Dump:
    config = replace(config_from_cfg({**cfg, "width": str(capacity.shape[0]), "height": str(capacity.shape[1])}),
                     initial_population=0)
    model = Model(config, capacity)
    for a in agents:
        max_age = math.inf if a.get("max_age") is None else a["max_age"]
        agent = model.new_agent(a["x"], a["y"], a["vision"], a["metabolism"], a["sugar"], max_age)
        agent.age = a.get("age", 0)
    model.run(steps)
    dump = Dump()
    for a in model.agents:
        dump.agents.append({"x": a.x, "y": a.y, "vision": a.vision, "metabolism": a.metabolism, "sugar": a.sugar,
                            "age": a.age, "max_age": None if math.isinf(a.max_age) else int(a.max_age),
                            "moved": int(a.moved), "neighbors": len(a.neighbors)})
    ls = model.landscape
    width, height = capacity.shape
    for x in range(width):
        for y in range(height):
            dump.landscape[(x, y)] = {"capacity": int(ls.capacity[x, y]), "sugar": float(ls.sugar[x, y]),
                                      "pollution": float(ls.pollution[x, y]),
                                      "occupied": int(model.agent_at(x, y) is not None)}
    return dump
