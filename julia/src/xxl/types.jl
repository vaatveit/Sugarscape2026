# xxl: a Julia-only rule set that uses the bigger world (docs/superpowers/specs/2026-10-28-xxl-design.md). This file
# holds the data types Config and the model need; it loads before config.jl.

const XXL_MAP = "sugar-map-xxl.txt"
const VISION_SHAPES = ("lattice", "disc")
const LANDSCAPES = ("xl", "generated")
const FOUNDER_PLACEMENTS = ("random", "viable")
const XXL_FOUNDER_AGES = ("book", "young")
const TRADE_MOVES = ("own", "local")
const TRADE_PRICES = ("meeting",)

"""
    XxlRules(; kw...)

The twenty-one xxl settings: the nine of the first spec ("The rules"), the four stage-1 survival switches of the
revised spec ("The changes"), the three stage-4 disease list settings (`disease_count`, `founder_diseases` and
`disease_lengths`), the three stage-5 trade move settings (`trade_move`, `trade_blend` and `trade_guard`) and the
stage-5b `trade_price` and the stage-5c `trade_step`, each at the book's value by default. The three list settings are `nothing` at the book's value:
they leave the experiment's own disease list, founder count and lengths as they are. `trade_move` is `nothing` (the
book's welfare score), `"own"` or `"local"` (the price an agent expects when it scores a site by trade); `trade_blend`
is a weight in [0, 1] (1 is the full rule) and `trade_guard` a number of periods or `nothing`; both need `trade_move`.
`trade_price` is `nothing` (the book's price, set afresh at each unit) or `"meeting"` (one price, set at the start of a
meeting, for every unit of it). `trade_step` is a number in (0, 1], the share of the book's unit a step trades (1 is the
book's unit; it needs `trade_rounding = "exact"` to be below 1).
The defaults are the book's settings, so `XxlRules()` changes nothing; [`XXL_V1`](@ref) is the xxl column of the first
spec's table and [`XXL_DEFAULTS`](@ref) the defaults stages 1 and 4 chose. `Config.xxl` holds one, or `nothing` for the
plain book rules.
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
    max_metabolism::Union{Nothing,Int} = nothing
    founder_placement::String = "random"
    free_step::Float64 = 0.0
    founder_ages::String = "book"
    disease_count::Union{Nothing,Int} = nothing
    founder_diseases::Union{Nothing,Int} = nothing
    disease_lengths::Union{Nothing,Tuple{Int,Int}} = nothing
    trade_move::Union{Nothing,String} = nothing
    trade_blend::Float64 = 1.0
    trade_guard::Union{Nothing,Int} = nothing
    trade_price::Union{Nothing,String} = nothing
    trade_step::Float64 = 1.0
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
The xxl defaults: [`XXL_V1`](@ref) with the stage-1 changes the scorecard chose (revised spec, "Tuning protocol";
docs/xxl.md, "Stage 1: the scorecard and survival"): the generated landscape, a free step of 1.5, viable founder
placement and a travel cost of 0.2. The metabolism cap and young founders were not needed and stay at their book
settings. Stage 4's list D, which the user adopted (docs/xxl.md, "Stage 4: the disease list"), sets the disease list:
3 diseases of length 9–10, with 1 offered to each founder. `--xxl` and the scorecard's `--rules defaults` run these;
the `XXL-…` experiments stay on `XXL_V1`.
"""
const XXL_DEFAULTS = replace_rules(
    XXL_V1;
    landscape="generated",
    free_step=1.5,
    founder_placement="viable",
    travel_cost=0.2,
    disease_count=3,
    founder_diseases=1,
    disease_lengths=(9, 10),
)

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
