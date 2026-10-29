# xxl: the transform from a regular config and the per-feature switches (spec, "The rules" and "Configuration").

"""
    to_xxl(cfg, rules=XXL_DEFAULTS) -> Config

The xxl version of a regular 50x50 config on `sugar-map.txt`: [`to_xl`](@ref) first (which refuses anything else,
and a config that is already xl), then `rules`. A run without seasons has no latitude to taper, so the season
gradient is turned off for it; the generated landscape swaps in `sugar-map-xxl.txt`.
"""
function to_xxl(cfg::Config, rules::XxlRules=XXL_DEFAULTS)
    xl = to_xl(cfg)
    cfg.seasons === nothing && (rules = replace_rules(rules; season_gradient=false))
    return replace_config(
        xl; xxl=rules, sugar_map=rules.landscape == "generated" ? XXL_MAP : xl.sugar_map
    )
end

"""
    xxl_on(cfg, feature) -> Bool

Whether `feature` (`:disc`, `:speed`, `:memory`, `:word_of_mouth`, `:radius`, `:gradient` or `:generated`) is away
from its book setting. False for every feature when `cfg.xxl` is `nothing`. Inlined, so that at a call site with a
literal feature the hot paths pay only the `nothing` check.
"""
@inline function xxl_on(cfg::Config, feature::Symbol)
    r = cfg.xxl
    r === nothing && return false
    feature === :disc && return r.vision_shape == "disc"
    feature === :speed && return r.speed !== nothing
    feature === :memory && return r.memory > 0
    feature === :word_of_mouth && return r.word_of_mouth
    feature === :radius && return r.interaction_radius != 1.0
    feature === :gradient && return r.season_gradient
    feature === :generated && return r.landscape == "generated"
    return throw(ArgumentError("unknown xxl feature $(repr(feature))"))
end
