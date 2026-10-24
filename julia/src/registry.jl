# The experiment registry, read from julia/registry.toml, which `python -m bridge.export_registry` writes from
# experiments/registry.py (Python stays the single source of truth).

const REGISTRY_PATH = joinpath(dirname(@__DIR__), "registry.toml")

"""One registered experiment: its config and xl config, and the Python fingerprints of both."""
struct Experiment
    id::String
    title::String
    rules::String
    steps::Int
    seeds::Int
    config::Config
    fingerprint::String
    xl_config::Config
    xl_fingerprint::String
end

function _field_value(name::Symbol, v)
    name === :initial_blocks && return Block[Tuple(b) for b in v]
    name === :block && return NTuple{4,Int}(v)
    name === :pollution && return (Float64(v[1]), Float64(v[2]))
    name === :credit && return (Int(v[1]), Float64(v[2]))
    v isa AbstractVector && return Tuple(Int.(v))
    return v
end

"""
    config_from_toml(d) -> Config

A validated Config from one exported table; fields missing from it keep their defaults (the exporter leaves out
`None` values, and every optional field defaults to `nothing`).
"""
function config_from_toml(d::AbstractDict)
    kw = Dict{Symbol,Any}()
    for (k, v) in d
        name = Symbol(k)
        name in fieldnames(Config) ||
            throw(ArgumentError("unknown Config field $k in the registry"))
        kw[name] = _field_value(name, v)
    end
    return validate(Config(; kw...))
end

"""
    load_registry(path=REGISTRY_PATH) -> Vector{Experiment}

Every exported experiment, in registry order.
"""
function load_registry(path::AbstractString=REGISTRY_PATH)
    data = TOML.parsefile(path)
    return [
        Experiment(
            e["id"],
            e["title"],
            e["rules"],
            e["steps"],
            e["seeds"],
            config_from_toml(e["config"]),
            e["fingerprint"],
            config_from_toml(e["xl_config"]),
            e["xl_fingerprint"],
        ) for e in data["experiment"]
    ]
end

function find_experiment(reg::AbstractVector{Experiment}, id::AbstractString)
    i = findfirst(e -> e.id == id, reg)
    i === nothing && throw(ArgumentError("no experiment $(repr(id)) in the registry"))
    return reg[i]
end
