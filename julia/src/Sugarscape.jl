"""
    Sugarscape

A port of the Python sugarscape model (`sugarscape/` in this repository) to Julia, for the implementation comparison
of docs/xl.md. The Python model is the specification; see docs/superpowers/specs/2026-10-24-julia-design.md.
"""
module Sugarscape

using Random: AbstractRNG, Xoshiro, shuffle!
using SHA: sha256
using TOML

export Config, validate, replace_config
export Experiment, REGISTRY_PATH, load_registry, find_experiment, config_from_toml
export MAPS_DIR, load_map, parse_map, map_sha256
export XL_FACTOR, XL_MAP, to_xl
export Agent, Exchange, Loan, sugar_burn
export Landscape, wrap, growback!, is_summer_north, seasonal_growback!, diffuse!
export Model,
    VON_NEUMANN,
    agent_at,
    neighbors_of,
    random_empty_site,
    new_agent!,
    spawn_random_agent!,
    spawn_at!
export move_agent!, kill!, die!, deaths_this_step, agents_ever, step!, run!, sample_distinct
export move!, metabolize!, pollution_active
export METRIC_COLUMNS, collect_metrics, gini, tribe, closeness

include("config.jl")
include("registry.jl")
include("maps.jl")
include("xl.jl")
include("agent.jl")
include("landscape.jl")
include("model.jl")
include("rules/movement.jl")
include("stats.jl")

end
