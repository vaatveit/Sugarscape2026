"""A registered Config as a run.cfg for the GPU program (Phase 1: Chapter II rules only)."""

import math

from bridge.paths import SUGARSCAPE_ROOT
from sugarscape.config import Config

# The Config fields the GPU program reads, in run.cfg order.
FIELDS = ("width", "height", "initial_population", "placement", "block", "vision", "metabolism", "endowment",
          "max_age", "founder_ages", "replacement", "growback_rate", "seasons", "winter_growback", "pollution",
          "pollution_start", "pollution_stop", "diffusion_period", "diffusion_start")


class UnsupportedFeature(ValueError):
    """The Config switches on a rule the GPU program does not implement yet."""


def unsupported_features(cfg: Config) -> list[str]:
    """The Chapter III-VI switches this Config turns on, and a non-default map."""
    switches = {
        "sex": cfg.sex,
        "inheritance": cfg.inheritance,
        "tag_length": cfg.tag_length > 0,
        "culture": cfg.culture,
        "combat_alpha": cfg.combat_alpha is not None,
        "initial_blocks": bool(cfg.initial_blocks),
        "replacement_same_tribe": cfg.replacement_same_tribe,
        "spice": cfg.spice,
        "trade": cfg.trade,
        "credit": cfg.credit is not None,
        "cultural_preferences": cfg.cultural_preferences,
        "foresight": cfg.foresight is not None,
        "disease_list": cfg.disease_list > 0,
        "diseases_per_agent": cfg.diseases_per_agent > 0,
        "sugar_map": cfg.sugar_map != "sugar-map.txt",
    }
    return [name for name, on in switches.items() if on]


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
