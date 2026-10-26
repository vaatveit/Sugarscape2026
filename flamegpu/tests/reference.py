"""The same scenario through the Python reference model (sugarscape.model.Model)."""

import math
from dataclasses import replace

import numpy as np

from bridge.paths import SUGARSCAPE_ROOT  # noqa: F401  (puts the Python project on sys.path)
from gpu import DEFAULT_CFG, Dump
from sugarscape.agent import Agent
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
    # Chapter III (spec 2026-10-25-gpu-full-parity, Part A).
    for key in ("sex", "inheritance", "culture"):
        kwargs[key] = values[key] == "true"
    for key in ("fertility_start", "female_fertility_end", "male_fertility_end"):
        kwargs[key] = tuple(int(v) for v in values[key].split(","))
    kwargs["tag_length"] = int(values["tag_length"])
    kwargs["initial_blocks"] = tuple((b[0], *(int(v) for v in b[1:])) for b in
                                     (block.split(",") for block in values["initial_blocks"].split(";") if block))
    for key in ("fertility_threshold", "child_share"):
        kwargs[key] = float(values[key])
    for key in ("mate_contact", "child_gift", "child_threshold", "gift_rounding"):
        kwargs[key] = values[key]
    return Config(**kwargs)


def build_python(cfg: dict, capacity: np.ndarray, agents: list[dict]) -> Model:
    """A Python model holding exactly `agents` (run_gpu's --init agents), with their Chapter III state."""
    config = replace(config_from_cfg({**cfg, "width": str(capacity.shape[0]), "height": str(capacity.shape[1])}),
                     initial_population=0, initial_blocks=())
    model = Model(config, capacity)
    for a in agents:
        max_age = math.inf if a.get("max_age") is None else a["max_age"]
        agent = model.new_agent(a["x"], a["y"], a["vision"], a["metabolism"], a["sugar"], max_age)
        agent.age = a.get("age", 0)
        if a.get("sex"):
            agent.sex = a["sex"]
            agent.fertility_start, agent.fertility_end = a["fertility_start"], a["fertility_end"]
        if a.get("initial_sugar") is not None:
            agent.initial_sugar = float(a["initial_sugar"])
        if a.get("tags") is not None:
            agent.tags = [int(c) for c in a["tags"]]
        # Children that died before the run: they count in mean_children (len(children)) and nowhere else.
        agent.children = [Agent(-1, -1, -1, 1, 1, 0.0, 0.0, 0, alive=False) for _ in range(a.get("n_children", 0))]
    # Parents given as the index (= uid) of another --init agent: the child joins their children (rule I's heirs).
    for a, agent in zip(agents, model.agents):
        for key in ("parent_a", "parent_b"):
            if a.get(key) is not None:
                model.agents[a[key]].children.append(agent)
        # Friends as "uid:distance|...", uids being --init indices.
        for item in filter(None, a.get("friends", "").split("|")):
            uid, dist = item.split(":")
            agent.friends.append((model.agents[int(uid)], int(dist)))
    return model


def python_metric_rows(cfg: dict, capacity: np.ndarray, agents: list[dict], steps: int) -> list[dict]:
    """sugarscape_metrics for t = 0 .. steps, as experiments.run records them."""
    from experiments.run import sugarscape_metrics

    model = build_python(cfg, capacity, agents)
    rows = [{"t": model.t, **sugarscape_metrics(model)}]
    for _ in range(steps):
        model.step()
        rows.append({"t": model.t, **sugarscape_metrics(model)})
    return rows


def run_python(cfg: dict, capacity: np.ndarray, agents: list[dict], steps: int) -> Dump:
    model = build_python(cfg, capacity, agents)
    model.run(steps)
    dump = Dump()
    for a in model.agents:
        dump.agents.append({"x": a.x, "y": a.y, "vision": a.vision, "metabolism": a.metabolism, "sugar": a.sugar,
                            "age": a.age, "max_age": None if math.isinf(a.max_age) else int(a.max_age),
                            "moved": int(a.moved), "neighbors": len(a.neighbors),
                            # Chapter III, in the GPU dump's spelling.
                            "uid": a.id, "sex": a.sex or "", "initial_sugar": a.initial_sugar,
                            "n_children": len(a.children),
                            "tags": "" if a.tags is None else "".join(str(t) for t in a.tags),
                            "friends": "|".join(f"{f.id}:{d}" for f, d in a.friends)})
    ls = model.landscape
    width, height = capacity.shape
    for x in range(width):
        for y in range(height):
            dump.landscape[(x, y)] = {"capacity": int(ls.capacity[x, y]), "sugar": float(ls.sugar[x, y]),
                                      "pollution": float(ls.pollution[x, y]),
                                      "occupied": int(model.agent_at(x, y) is not None)}
    return dump
