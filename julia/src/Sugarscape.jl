"""
    Sugarscape

A port of the Python sugarscape model (`sugarscape/` in this repository) to Julia, for the implementation comparison
of docs/xl.md. The Python model is the specification; see docs/superpowers/specs/2026-10-24-julia-design.md.
"""
module Sugarscape

using Distributed: WorkerPool, addprocs, pmap, remotecall_eval, rmprocs
using Random: AbstractRNG, Xoshiro, shuffle!
using SHA: sha256
using TOML

export Config, validate, replace_config
export Experiment, REGISTRY_PATH, load_registry, find_experiment, config_from_toml
export MAPS_DIR, load_map, parse_map, map_sha256
export XL_FACTOR, XL_MAP, to_xl
export XxlRules, XXL_BOOK, XXL_DEFAULTS, XXL_MAP, replace_rules, to_xxl, xxl_on
export torus_delta,
    torus_dist, disc_offsets, near_offsets, ring_point, ring_draws, winter_weight
export Remembered
export Agent, Exchange, Loan, sugar_burn
export Landscape, wrap, growback!, is_summer_north, seasonal_growback!, diffuse!, set_spice!
export Model,
    VON_NEUMANN,
    agent_at,
    neighbors_of,
    random_empty_site,
    new_agent!,
    spawn_random_agent!,
    spawn_at!
export move_agent!, kill!, die!, deaths_this_step, agents_ever, step!, run!, sample_distinct
export move!, metabolize!, pollution_active, look_distance, look_distances
export METRIC_COLUMNS, collect_metrics, gini, tribe, closeness
export random_tags, cross_tags, hamming, culture_transmit!, update_friends!
export is_fertile, assign_sex!, in_sight, mate!, combat_move!, vulnerable
export preference_fraction, welfare, mrs, welfare_score, bargain!, trade_with_neighbors!
export available_to_lend,
    shortfall, creditworthy, seek_credit!, settle_loans!, credit_on_death!

export intern_disease!,
    nearest_substring, is_immune, immune_step!, infect!, immune_response!
export disease_transmit!

include("xxl/types.jl")
include("config.jl")
include("registry.jl")
include("maps.jl")
include("xl.jl")
include("xxl/transform.jl")
include("agent.jl")
include("landscape.jl")
include("model.jl")
include("xxl/geometry.jl")
include("rules/movement.jl")
include("rules/culture.jl")
include("rules/sex.jl")
include("rules/combat.jl")
include("rules/welfare.jl")
include("rules/trade.jl")
include("rules/credit.jl")
include("rules/disease.jl")
include("stats.jl")
include("runner.jl")

end
