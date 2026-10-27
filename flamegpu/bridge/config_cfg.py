"""A registered Config as a run.cfg for the GPU program: Chapters II to V (spec 2026-10-25-gpu-full-parity, Parts A
to D)."""

import math
from dataclasses import MISSING, Field, fields

from bridge.paths import SUGARSCAPE_ROOT
from sugarscape.config import Config

# The Config fields the GPU program reads, in run.cfg order.
FIELDS = ("width", "height", "initial_population", "placement", "block", "vision", "metabolism", "endowment",
          "max_age", "founder_ages", "replacement", "growback_rate", "seasons", "winter_growback", "pollution",
          "pollution_start", "pollution_stop", "diffusion_period", "diffusion_start", "diffusion_passes",
          "look_stride",
          # Chapter III without combat (Part A).
          "sex", "fertility_start", "female_fertility_end", "male_fertility_end", "inheritance", "tag_length",
          "culture", "initial_blocks", "fertility_threshold", "child_share", "mate_contact", "child_gift",
          "child_threshold", "gift_rounding",
          # Combat and same-tribe replacement (Part B).
          "combat_alpha", "replacement_same_tribe",
          # Chapter IV (Part C).
          "spice", "spice_metabolism", "spice_endowment", "foresight", "cultural_preferences", "trade",
          "trade_rounding", "credit",
          # Chapter V (Part D).
          "disease_list", "diseases_per_agent", "disease_length", "immune_length", "disease_fee")
# Read too, but written as run.cfg's map path rather than as its own line.
READ_AS_MAP = "sugar_map"


class UnsupportedFeature(ValueError):
    """The Config switches on a rule the GPU program does not implement yet."""


def _default(f: Field):
    return f.default_factory() if f.default is MISSING else f.default


def unsupported_features(cfg: Config) -> list[str]:
    """Every Config field the GPU program does not read (FIELDS, the map and the seed) that is not at its default.

    Fields left out of repr count too, and so does any field the Python project adds later: a setting the GPU
    cannot honour is refused, never dropped.
    """
    return [f.name for f in fields(cfg)
            if f.name not in FIELDS and f.name not in (READ_AS_MAP, "seed") and getattr(cfg, f.name) != _default(f)]


def _value(v) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and math.isinf(v):
        return "inf"
    if isinstance(v, tuple) and v and isinstance(v[0], tuple):  # initial_blocks: one tribe,x0,y0,w,h,n per block
        return ";".join(_value(x) for x in v)
    if isinstance(v, tuple):
        return ",".join(_value(x) for x in v)
    return repr(v) if isinstance(v, float) else str(v)


def config_to_cfg(cfg: Config, steps: int, seed: int) -> str:
    """run.cfg text for this Config; raises UnsupportedFeature naming the rules not on the GPU yet."""
    missing = unsupported_features(cfg)
    if missing:
        raise UnsupportedFeature(f"not on the GPU yet: {', '.join(missing)}")
    lines = [f"{name} = {_value(getattr(cfg, name))}" for name in FIELDS]
    lines += [f"map = {SUGARSCAPE_ROOT / 'sugarscape' / 'maps' / cfg.sugar_map}", f"steps = {steps}", f"seed = {seed}"]
    return "\n".join(lines) + "\n"
