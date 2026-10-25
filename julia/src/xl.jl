# xl: the sugarscape at 10x the linear resolution, 500x500 (docs/xl.md, "The configuration"). Anything measured in
# sites scales by 10 along each side, anything counted per area by 100, anything per agent, site or period is
# unchanged.

const XL_FACTOR = 10
const XL_MAP = "sugar-map-xl.txt"
const XL_BASE_MAP = "sugar-map.txt"
const XL_BASE_SIZE = 50

"""
    to_xl(cfg) -> Config

The xl version of a regular 50x50 config on `sugar-map.txt`; anything else is refused.
"""
function to_xl(cfg::Config)
    (cfg.width, cfg.height, cfg.sugar_map) == (XL_BASE_SIZE, XL_BASE_SIZE, XL_BASE_MAP) ||
        throw(
            ArgumentError(
                "xl applies to the $(XL_BASE_SIZE)x$(XL_BASE_SIZE) $XL_BASE_MAP world, " *
                "not $(cfg.width)x$(cfg.height) on $(cfg.sugar_map)",
            ),
        )
    f = XL_FACTOR
    lo, hi = cfg.vision
    return replace_config(
        cfg;
        width=cfg.width * f,
        height=cfg.height * f,
        sugar_map=XL_MAP,
        initial_population=cfg.initial_population * f * f,
        vision=(lo * f, hi * f),
        block=map(v -> v * f, cfg.block),
        initial_blocks=Block[
            (t, x0 * f, y0 * f, w * f, h * f, n * f * f) for
            (t, x0, y0, w, h, n) in cfg.initial_blocks
        ],
        diffusion_passes=cfg.diffusion_passes * f * f,
        look_stride=cfg.look_stride * f,  # as many sites per look as a regular agent, over the same distance
    )
end
