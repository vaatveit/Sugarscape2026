# Run configuration: every rule toggle and parameter, ported from sugarscape/config.py with the same names and
# defaults. Book page references are to Epstein & Axtell (1996); "our call" readings are documented there.

const PLACEMENTS = ("random", "block")
const WINTER_MODES = ("fractional", "pulse")
const TRIBES = ("blue", "red")
const FOUNDER_AGES = ("uniform", "zero")
const MATE_CONTACTS = ("neighbors", "vision")
const CHILD_GIFTS = ("endowment", "capped")
const CHILD_THRESHOLDS = ("endowment", "redraw")
const GIFT_ROUNDINGS = ("exact", "down")
const TRADE_ROUNDINGS = ("exact", "down")

# Tags and immune strings are bit fields (design, "Free to differ"): the one place Julia refuses a config Python
# accepts. The registry uses 11 tags and 50-bit immune systems.
const MAX_TAG_LENGTH = 63
const MAX_IMMUNE_LENGTH = 64

const Range = Tuple{Int,Int}
const Block = Tuple{String,Int,Int,Int,Int,Int}

"""
    Config(; kw...)

One run's settings, field for field the Python `Config`. Construction does not validate; [`validate`](@ref) does,
and [`replace_config`](@ref) and the registry loader call it.
"""
Base.@kwdef struct Config
    # World (p.21: 50x50 torus).
    width::Int = 50
    height::Int = 50
    sugar_map::String = "sugar-map.txt"

    # Initial population (p.23: 400 random agents).
    initial_population::Int = 400
    placement::String = "random"
    block::NTuple{4,Int} = (0, 0, 20, 20)

    # Genetics and endowment, each an inclusive uniform integer range.
    vision::Range = (1, 6)
    metabolism::Range = (1, 4)
    endowment::Range = (5, 25)
    max_age::Union{Nothing,Range} = nothing
    founder_ages::String = "uniform"
    replacement::Bool = false

    # Environment.
    growback_rate::Float64 = 1.0
    seasons::Union{Nothing,Range} = nothing
    winter_growback::String = "fractional"
    pollution::Union{Nothing,Tuple{Float64,Float64}} = nothing
    pollution_start::Int = 0
    diffusion_period::Union{Nothing,Int} = nothing
    diffusion_start::Int = 0
    diffusion_passes::Int = 1
    # Along each lattice line, agents look at one random site in each stretch of look_stride sites (rules M and C,
    # and rule S's partners in sight), and vision is drawn in whole strides. xl sets 10 (docs/xl.md, "Looking").
    look_stride::Int = 1

    # Chapter III.
    sex::Bool = false
    fertility_start::Range = (12, 15)
    female_fertility_end::Range = (40, 50)
    male_fertility_end::Range = (50, 60)
    inheritance::Bool = false
    tag_length::Int = 0
    culture::Bool = false
    combat_alpha::Union{Nothing,Float64} = nothing
    initial_blocks::Vector{Block} = Block[]
    replacement_same_tribe::Bool = false
    fertility_threshold::Float64 = 1.0
    child_share::Float64 = 0.5
    mate_contact::String = "vision"
    child_gift::String = "endowment"
    child_threshold::String = "endowment"
    gift_rounding::String = "down"

    # Chapter IV.
    spice::Bool = false
    spice_metabolism::Range = (1, 5)
    spice_endowment::Union{Nothing,Range} = nothing
    foresight::Union{Nothing,Range} = nothing
    cultural_preferences::Bool = false
    trade::Bool = false
    trade_rounding::String = "exact"
    credit::Union{Nothing,Tuple{Int,Float64}} = nothing
    pollution_stop::Union{Nothing,Int} = nothing

    # Chapter V.
    disease_list::Int = 0
    diseases_per_agent::Int = 0
    disease_length::Range = (1, 10)
    immune_length::Int = 50
    disease_fee::Float64 = 1.0

    seed::Int = 0
end

function Base.:(==)(a::Config, b::Config)
    return all(getfield(a, f) == getfield(b, f) for f in fieldnames(Config))
end
function Base.hash(c::Config, h::UInt)
    return foldl(
        (acc, f) -> hash(getfield(c, f), acc), fieldnames(Config); init=hash(:Config, h)
    )
end

"""
    replace_config(cfg; kw...) -> Config

A copy of `cfg` with the given fields changed, validated (Python's `dataclasses.replace`). Not named `with`, which
Base exports.
"""
function replace_config(cfg::Config; kw...)
    values = Dict{Symbol,Any}(f => getfield(cfg, f) for f in fieldnames(Config))
    for (k, v) in kw
        k in fieldnames(Config) || throw(ArgumentError("Config has no field $k"))
        values[k] = v
    end
    return validate(Config(; values...))
end

bad(msg) = throw(ArgumentError(msg))

function check_range(name, r)
    return (r !== nothing && r[1] > r[2]) && bad("$name range $r has low > high")
end

function check_option(name, value, allowed)
    return value in allowed || bad("$name must be one of $allowed, not $(repr(value))")
end

"""
    validate(cfg) -> cfg

Every check of Python's `Config.__post_init__`, plus the bit-field limits; throws `ArgumentError`.
"""
function validate(c::Config)
    for name in (:vision, :metabolism, :endowment, :max_age)
        check_range(name, getfield(c, name))
    end
    # Agents see only along the four lattice directions; a vision of half the grid or more would let opposite scans
    # reach the same sites (Kehoe: MAXVISION << M).
    c.vision[2] * 2 >= min(c.width, c.height) && bad(
        "max vision $(c.vision[2]) must be less than half the grid ($(c.width)x$(c.height))",
    )
    c.replacement &&
        c.max_age === nothing &&
        bad("replacement R[a,b] needs a max_age range [a, b]")
    check_option(:mate_contact, c.mate_contact, MATE_CONTACTS)
    check_option(:child_gift, c.child_gift, CHILD_GIFTS)
    check_option(:child_threshold, c.child_threshold, CHILD_THRESHOLDS)
    check_option(:gift_rounding, c.gift_rounding, GIFT_ROUNDINGS)
    check_option(:trade_rounding, c.trade_rounding, TRADE_ROUNDINGS)
    check_option(:founder_ages, c.founder_ages, FOUNDER_AGES)
    check_option(:placement, c.placement, PLACEMENTS)
    check_option(:winter_growback, c.winter_growback, WINTER_MODES)
    c.initial_population < 0 &&
        bad("initial_population must be >= 0, not $(c.initial_population)")
    c.growback_rate < 0 && bad("growback_rate must be >= 0, not $(c.growback_rate)")
    c.seasons !== nothing &&
        minimum(c.seasons) < 1 &&
        bad("seasons (beta, gamma) must both be >= 1, not $(c.seasons)")
    c.diffusion_period !== nothing &&
        c.diffusion_period < 1 &&
        bad("diffusion_period must be None or >= 1, not $(c.diffusion_period)")
    c.diffusion_passes < 1 &&
        bad("diffusion_passes must be a whole number >= 1, not $(c.diffusion_passes)")
    c.look_stride < 1 &&
        bad("look_stride must be a whole number >= 1, not $(c.look_stride)")
    (c.vision[1] % c.look_stride != 0 || c.vision[2] % c.look_stride != 0) &&
        bad("vision range $(c.vision) must be in whole look strides of $(c.look_stride)")
    c.pollution !== nothing &&
        minimum(c.pollution) < 0 &&
        bad("pollution coefficients must be >= 0, not $(c.pollution)")
    for name in (:fertility_start, :female_fertility_end, :male_fertility_end)
        check_range(name, getfield(c, name))
    end
    (c.tag_length < 0 || (c.tag_length > 0 && iseven(c.tag_length))) &&
        bad("tag_length must be 0 or odd (so groups have a majority), not $(c.tag_length)")
    c.tag_length > MAX_TAG_LENGTH &&
        bad("tag_length above $MAX_TAG_LENGTH is not supported in Julia (bit field)")
    c.immune_length > MAX_IMMUNE_LENGTH &&
        bad("immune_length above $MAX_IMMUNE_LENGTH is not supported in Julia (bit field)")
    c.tag_length == 0 &&
        (c.culture || c.combat_alpha !== nothing || !isempty(c.initial_blocks)) &&
        bad("culture, combat, and tribal blocks need cultural tags (tag_length > 0)")
    c.combat_alpha !== nothing &&
        c.combat_alpha < 0 &&
        bad("combat_alpha must be >= 0, not $(c.combat_alpha)")
    for blk in c.initial_blocks
        tribe, x0, y0, bw, bh, n = blk
        tribe in TRIBES || bad("block tribe must be one of $TRIBES, not $(repr(tribe))")
        (
            0 <= x0 &&
            0 <= y0 &&
            x0 + bw <= c.width &&
            y0 + bh <= c.height &&
            bw >= 1 &&
            bh >= 1
        ) || bad("block $blk must lie inside the $(c.width)x$(c.height) grid")
        0 <= n <= bw * bh || bad("block $blk cannot hold $n agents")
    end
    for name in (:spice_metabolism, :spice_endowment, :foresight)
        check_range(name, getfield(c, name))
    end
    !c.spice &&
        (c.trade || c.cultural_preferences || c.foresight !== nothing) &&
        bad(
            "trade, cultural preferences, and foresight need the second commodity (spice=True)",
        )
    c.cultural_preferences &&
        c.tag_length == 0 &&
        bad("cultural preferences need cultural tags (tag_length > 0)")
    c.spice &&
        c.combat_alpha !== nothing &&
        bad("combat is defined for sugar only (p.83); not with spice")
    if c.credit !== nothing
        d, r = c.credit
        c.sex || bad("credit L_dr lends for childbearing; it needs sex=True")
        c.combat_alpha !== nothing &&
            bad("credit needs each agent's income, which combat movement doesn't record")
        (d < 1 || r < 0) &&
            bad("credit duration must be >= 1 and rate >= 0, not $(c.credit)")
    end
    (c.disease_list < 0 || c.diseases_per_agent < 0) &&
        bad("disease_list and diseases_per_agent must be >= 0")
    c.diseases_per_agent > c.disease_list && bad(
        "cannot offer $(c.diseases_per_agent) distinct diseases from a list of $(c.disease_list)",
    )
    (c.disease_length[1] < 1 || c.disease_length[1] > c.disease_length[2]) &&
        bad("disease_length $(c.disease_length) must be a range starting at >= 1")
    c.disease_length[2] >= c.immune_length &&
        bad("diseases must be shorter than immune systems (p.141)")
    c.disease_fee < 0 && bad("disease_fee must be >= 0, not $(c.disease_fee)")
    c.pollution_stop !== nothing &&
        c.pollution_stop <= c.pollution_start &&
        bad("pollution_stop must come after pollution_start")
    c.fertility_threshold <= 0 &&
        bad("fertility_threshold must be > 0, not $(c.fertility_threshold)")
    0 < c.child_share <= 1 || bad("child_share must lie in (0, 1], not $(c.child_share)")
    c.replacement_same_tribe &&
        !c.replacement &&
        bad("replacement_same_tribe needs replacement=True")
    _, _, w, h = c.block
    c.placement == "block" &&
        !(1 <= w <= c.width && 1 <= h <= c.height) &&
        bad("block $(c.block) must have 1 <= w <= $(c.width) and 1 <= h <= $(c.height)")
    return c
end
