"""
    Sugarscape

A port of the Python sugarscape model (`sugarscape/` in this repository) to Julia, for the implementation comparison
of docs/xl.md. The Python model is the specification; see docs/superpowers/specs/2026-10-24-julia-design.md.
"""
module Sugarscape

using SHA: sha256
using TOML

export Config, validate, replace_config
export Experiment, REGISTRY_PATH, load_registry, find_experiment, config_from_toml
export MAPS_DIR, load_map, parse_map, map_sha256
export XL_FACTOR, XL_MAP, to_xl

include("config.jl")
include("registry.jl")
include("maps.jl")
include("xl.jl")

end
