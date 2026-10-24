"""A registered Config as a run.cfg for the GPU program (Phase 1: Chapter II rules only)."""

import math
from dataclasses import MISSING, Field, fields

from bridge.paths import SUGARSCAPE_ROOT
from sugarscape.config import Config

# The Config fields the GPU program reads, in run.cfg order.
FIELDS = ("width", "height", "initial_population", "placement", "block", "vision", "metabolism", "endowment",
          "max_age", "founder_ages", "replacement", "growback_rate", "seasons", "winter_growback", "pollution",
          "pollution_start", "pollution_stop", "diffusion_period", "diffusion_start")


class UnsupportedFeature(ValueError):
    """The Config switches on a rule the GPU program does not implement yet."""


def _default(f: Field):
    return f.default_factory() if f.default is MISSING else f.default


def unsupported_features(cfg: Config) -> list[str]:
    """Every Config field the GPU program does not read (FIELDS, plus the seed) that is not at its default.

    The map is among them, so only the default sugar-map.txt runs. Fields left out of repr count too, and so does
    any field the Python project adds later: a setting the GPU cannot honour is refused, never dropped.
    """
    return [f.name for f in fields(cfg)
            if f.name not in FIELDS and f.name != "seed" and getattr(cfg, f.name) != _default(f)]


def _value(v) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and math.isinf(v):
        return "inf"
    if isinstance(v, tuple):
        return ",".join(_value(x) for x in v)
    return repr(v) if isinstance(v, float) else str(v)


def config_to_cfg(cfg: Config, steps: int, seed: int) -> str:
    """run.cfg text for this Config; raises UnsupportedFeature naming the rules Phase 1 lacks."""
    missing = unsupported_features(cfg)
    if missing:
        raise UnsupportedFeature(f"not supported on the GPU in Phase 1: {', '.join(missing)}")
    lines = [f"{name} = {_value(getattr(cfg, name))}" for name in FIELDS]
    lines += [f"map = {SUGARSCAPE_ROOT / 'sugarscape' / 'maps' / cfg.sugar_map}", f"steps = {steps}", f"seed = {seed}"]
    return "\n".join(lines) + "\n"
