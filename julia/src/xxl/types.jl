# xxl: a Julia-only rule set that uses the bigger world (docs/superpowers/specs/2026-10-28-xxl-design.md). This file
# holds the data types Config and the model need; it loads before config.jl.

const XXL_MAP = "sugar-map-xxl.txt"
const VISION_SHAPES = ("lattice", "disc")
const LANDSCAPES = ("xl", "generated")

"""
    XxlRules(; kw...)

The nine xxl settings (spec, "The rules"). The defaults are the book's settings, so `XxlRules()` changes nothing;
[`XXL_DEFAULTS`](@ref) is the xxl column of the spec's table. `Config.xxl` holds one, or `nothing` for the plain
book rules.
"""
Base.@kwdef struct XxlRules
    vision_shape::String = "lattice"
    speed::Union{Nothing,Tuple{Int,Int}} = nothing
    travel_cost::Float64 = 0.0
    memory::Int = 0
    memory_span::Int = 50
    word_of_mouth::Bool = false
    interaction_radius::Float64 = 1.0
    season_gradient::Bool = false
    landscape::String = "xl"
end

function Base.:(==)(a::XxlRules, b::XxlRules)
    return all(getfield(a, f) == getfield(b, f) for f in fieldnames(XxlRules))
end
function Base.hash(r::XxlRules, h::UInt)
    return foldl(
        (acc, f) -> hash(getfield(r, f), acc), fieldnames(XxlRules); init=hash(:XxlRules, h)
    )
end

"Every xxl setting at the book's value (the book column of the spec's table)."
const XXL_BOOK = XxlRules()

"The first xxl rules, frozen: the xxl column of the first spec's table. Later changes to the defaults leave these alone."
const XXL_V1 = XxlRules(;
    vision_shape="disc",
    speed=(1, 6),
    travel_cost=0.1,
    memory=8,
    memory_span=50,
    word_of_mouth=true,
    interaction_radius=1.5,
    season_gradient=true,
    landscape="xl",
)

"The xxl default column of the spec's table; for now the first rules."
const XXL_DEFAULTS = XXL_V1

"""
    replace_rules(rules; kw...) -> XxlRules

A copy of `rules` with the given fields changed. Not validated here; `Config`'s validation checks the rules against
the rest of the run.
"""
function replace_rules(r::XxlRules; kw...)
    values = Dict{Symbol,Any}(f => getfield(r, f) for f in fieldnames(XxlRules))
    for (k, v) in kw
        k in fieldnames(XxlRules) || throw(ArgumentError("XxlRules has no field $k"))
        values[k] = v
    end
    return XxlRules(; values...)
end

"""
    Remembered

A site an xxl agent remembers (spec, "Memory"): its coordinates, the raw sugar and spice it showed when last seen,
the pollution as seen, and the period `t` of the sighting.
"""
struct Remembered
    x::Int
    y::Int
    sugar::Float64
    spice::Float64
    pollution::Float64
    t::Int
end
