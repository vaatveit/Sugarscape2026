"""xl: the sugarscape at 10x the linear resolution, 500x500, for comparing implementations (docs/xl.md).

Everything measured in cells scales by 10 along each side, everything counted per area by 100, and everything per
agent, per cell or per period is unchanged, so an xl run looks like a regular run, only more detailed.
"""

from dataclasses import replace

from sugarscape.config import Config
from sugarscape.maps.xl import FACTOR, XL_MAP

DIFFUSION_PASSES = FACTOR * FACTOR  # spread grows as the square root of the passes: 100 passes cover 10x the cells
BASE_MAP = "sugar-map.txt"
BASE_SIZE = 50


def to_xl(cfg: Config) -> Config:
    """The xl version of a regular 50x50 config (docs/xl.md, "The configuration")."""
    if (cfg.width, cfg.height, cfg.sugar_map) != (BASE_SIZE, BASE_SIZE, BASE_MAP):
        raise ValueError(f"xl applies to the {BASE_SIZE}x{BASE_SIZE} {BASE_MAP} world, "
                         f"not {cfg.width}x{cfg.height} on {cfg.sugar_map}")
    lo, hi = cfg.vision
    return replace(
        cfg,
        width=cfg.width * FACTOR,
        height=cfg.height * FACTOR,
        sugar_map=XL_MAP,
        initial_population=cfg.initial_population * FACTOR * FACTOR,
        vision=(lo * FACTOR, hi * FACTOR),  # drawn in whole look strides: 10, 20, ... (user decision 2026-10-24)
        block=tuple(v * FACTOR for v in cfg.block),
        initial_blocks=tuple((tribe, x0 * FACTOR, y0 * FACTOR, w * FACTOR, h * FACTOR, n * FACTOR * FACTOR)
                             for tribe, x0, y0, w, h, n in cfg.initial_blocks),
        diffusion_passes=cfg.diffusion_passes * DIFFUSION_PASSES,
        look_stride=cfg.look_stride * FACTOR,  # as many cells per look as a regular agent, over the same distance
    )
