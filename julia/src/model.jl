# The model: agents on a landscape, advanced one period at a time by `step!` (sugarscape/model.py).

const VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))  # E, W, N, S

# Every order of the four directions; drawing one uniformly is a uniform random permutation (rng.permutation(4)).
const DIRECTION_ORDERS = let orders = NTuple{4,Int}[]
    for a in 1:4, b in 1:4, c in 1:4, d in 1:4
        length(Set((a, b, c, d))) == 4 && push!(orders, (a, b, c, d))
    end
    orders
end

random_directions(rng::AbstractRNG) = @inbounds DIRECTION_ORDERS[rand(rng, 1:24)]

mutable struct Model{R<:AbstractRNG}
    config::Config
    rng::R  # Xoshiro(seed) unless a caller supplies one (the lockstep test replays Python's choices)
    landscape::Landscape
    grid::Matrix{Union{Nothing,Agent}}
    agents::Vector{Agent}  # the living, in no particular order (each period draws a fresh order)
    t::Int
    dead_this_step::Vector{Agent}
    trade_log::Vector{Exchange}  # this period's exchanges (rule T)
    loans::Vector{Loan}  # active loans (rule L), in creation order
    debts::Dict{Int,Vector{Loan}}  # each borrower's loans by id, in the loan book's order (creditworthy)
    lent::Dict{Int,Int}  # how many loans each lender has made, by id (deaths without loans skip rule L)
    next_id::Int
    infection_log::Vector{Tuple{Agent,Agent}}  # this period's (source, target) infections
    disease_list::Vector{Int}  # the master list (p.147), as interned disease ids
    disease_bits::Vector{UInt64}  # interned diseases: bit string and length, by id
    disease_len::Vector{Int}
    disease_ids::Dict{Tuple{UInt64,Int},Int}
    order::Vector{Agent}  # scratch: this period's acting order
    line::Vector{Int}  # scratch: move! and combat_move!'s look distances along one line
    threat::Vector{Int}  # scratch: vulnerable's look distances along one line
    looks::Vector{Int}  # scratch: in_sight's looks across the four lines, nearest first
    sight::Vector{Agent}  # scratch: in_sight's agents, nearest first
    sites::Vector{Tuple{Int,Int}}  # scratch: mate!'s empty sites next to the parents
    near::Dict{Float64,Vector{Tuple{Int,Int}}}  # xxl: disc offsets by radius (near_offsets)
    looked::Vector{Tuple{Int,Int}}  # xxl scratch: this move's looked-at sites
    shell_shares::Vector{Float64}  # xxl: the clustering cache, empty until first used
    threat_looked::Vector{Tuple{Int,Int}}  # xxl scratch: the retaliation look's sites, apart from `looked`
    pool::Vector{Remembered}  # xxl scratch: memory ranking's candidates (rule 3)
    pool_values::Vector{Float64}  # xxl scratch: the kept entries' net values
    viable_fallbacks::Int  # xxl: new agents placed off viable land because none was free (spawn_viable!)
    viable_sites::Dict{Tuple{Int,Int},Vector{Int32}}  # xxl: the grid's viable sites by metabolism pair, built lazily
    killed::Set{Int}  # xxl: ids of the agents killed in combat this period (xxl_combat_move!), for the scorecard
end

"""
    Model(cfg; capacity=nothing, rng=Xoshiro(cfg.seed))

Builds the world and its founders as `Model.__init__` does, drawing in Python's gated order: the disease master
list, the founders (Chapter II draws, then III, IV, V as enabled), initial infections, then founder ages.
"""
function Model(
    cfg::Config;
    capacity::Union{Nothing,AbstractMatrix{<:Integer}}=nothing,
    rng::AbstractRNG=Xoshiro(cfg.seed),
)
    validate(cfg)
    cap = capacity === nothing ? load_map(cfg.sugar_map) : Matrix{Int}(capacity)
    size(cap) == (cfg.width, cfg.height) ||
        throw(ArgumentError("capacity shape $(size(cap)) != ($(cfg.width), $(cfg.height))"))
    # Fig IV-1: spice mountains NW and SE, i.e. the sugar map mirrored east-west. The generated landscape (xxl rule 6)
    # has a spice map of its own: the mirror is a fact of the book's map, not a law.
    spice_cap = if !cfg.spice
        nothing
    elseif xxl_on(cfg, :generated)
        load_map(XXL_SPICE_MAP)
    else
        reverse(cap; dims=1)
    end
    ls = Landscape(cap, spice_cap)
    m = Model(
        cfg,
        rng,
        ls,
        fill!(Matrix{Union{Nothing,Agent}}(undef, cfg.width, cfg.height), nothing),
        Agent[],
        0,
        Agent[],
        Exchange[],
        Loan[],
        Dict{Int,Vector{Loan}}(),
        Dict{Int,Int}(),
        0,
        Tuple{Agent,Agent}[],
        Int[],
        UInt64[],
        Int[],
        Dict{Tuple{UInt64,Int},Int}(),
        Agent[],
        Int[],
        Int[],
        Int[],
        Agent[],
        Tuple{Int,Int}[],
        Dict{Float64,Vector{Tuple{Int,Int}}}(),
        Tuple{Int,Int}[],
        Float64[],
        Tuple{Int,Int}[],
        Remembered[],
        Float64[],
        0,
        Dict{Tuple{Int,Int},Vector{Int32}}(),
        Set{Int}(),
    )
    cfg.disease_list > 0 && init_disease_list!(m)
    place_initial_population!(m)
    cfg.diseases_per_agent > 0 && infect_founders!(m)
    # Founders of a society with finite lives start at ages U[0, max age) (Config.founder_ages). Drawn last, and
    # only with finite lives. xxl founder_ages = "young" (revised spec, "Stage 1: survival", change 4) draws U[0, fertility
    # start] instead, in the same loop and position; it needs sex (the fertility start) as well as finite lives, and it
    # leaves the book's founder_ages = "zero" alone.
    if cfg.max_age !== nothing && cfg.founder_ages == "uniform"
        young = cfg.sex && xxl_on(cfg, :young)
        for a in m.agents
            a.age = if young
                rand(m.rng, 0:Int(a.fertility_start))
            else
                rand(m.rng, 0:(Int(a.max_age) - 1))
            end
        end
    end
    return m
end

# --- occupancy -----------------------------------------------------------------------

wrap(m::Model, x::Int, y::Int) = wrap(m.landscape, x, y)

@inline function agent_at(m::Model, x::Int, y::Int)
    x, y = wrap(m.landscape, x, y)
    return @inbounds m.grid[x + 1, y + 1]
end

"""
Living agents on the four von Neumann sites around `a` (p.39), in the order E, W, N, S. Under xxl rule 4 (interaction
radius R ≠ 1): those within R, nearest first.
"""
function neighbors_of(m::Model, a::Agent)
    found = Agent[]
    xxl_on(m.config, :radius) && return radius_neighbors!(found, m, a)
    for (dx, dy) in VON_NEUMANN
        other = agent_at(m, a.x + dx, a.y + dy)
        other === nothing || push!(found, other)
    end
    return found
end

"""A uniformly random empty site, or `nothing` when the lattice is full."""
function random_empty_site(m::Model)
    w, h = m.config.width, m.config.height
    for _ in 1:64
        x, y = rand(m.rng, 0:(w - 1)), rand(m.rng, 0:(h - 1))
        m.grid[x + 1, y + 1] === nothing && return (x, y)
    end
    empty = count(isnothing, m.grid)
    empty == 0 && return nothing
    k = rand(m.rng, 1:empty)
    for i in eachindex(m.grid)
        if m.grid[i] === nothing
            k -= 1
            k == 0 && return ((i - 1) % w, (i - 1) ÷ w)
        end
    end
end

function new_agent!(
    m::Model, x::Int, y::Int, vision::Int, metabolism::Int, sugar::Real; max_age::Real=Inf
)
    x, y = wrap(m, x, y)
    m.grid[x + 1, y + 1] === nothing || throw(ArgumentError("site ($x, $y) is occupied"))
    return place_agent!(
        m, build_agent!(m, vision, metabolism, sugar; max_age=max_age), x, y
    )
end

"""An agent with the next id, not yet on the grid: the first half of `new_agent!` (`spawn_viable!` places it later)."""
function build_agent!(
    m::Model, vision::Int, metabolism::Int, sugar::Real; max_age::Real=Inf
)
    a = Agent(m.next_id, 0, 0, vision, metabolism, Float64(sugar), Float64(max_age))
    m.next_id += 1
    return a
end

"""Puts the unplaced agent `a` on the empty site (x, y) and among the living: the second half of `new_agent!`."""
function place_agent!(m::Model, a::Agent, x::Int, y::Int)
    a.x, a.y = x, y
    m.grid[x + 1, y + 1] = a
    push!(m.agents, a)
    a.slot = length(m.agents)
    return a
end

"""
    spawn_random_agent!(m; tribe=:none)

A new agent with random genetics, endowment and max age at a random empty site (R, p.32). With a tribe, its random
tags are drawn to belong to that tribe (same-tribe R, p.86).
"""
function spawn_random_agent!(m::Model; tribe::Symbol=:none)
    if xxl_on(m.config, :viable)  # xxl: traits first, then a site that feeds them (xxl/placement.jl)
        length(m.agents) < length(m.grid) ||
            throw(ArgumentError("no empty site for a new agent: the lattice is full"))
        return spawn_viable!(m, grid_sites(m), m.viable_sites; tribe=tribe)
    end
    site = random_empty_site(m)
    site === nothing &&
        throw(ArgumentError("no empty site for a new agent: the lattice is full"))
    return spawn_at!(m, site...; tribe=tribe)
end

function move_agent!(m::Model, a::Agent, x::Int, y::Int)
    x, y = wrap(m, x, y)
    if (x, y) == (a.x, a.y)
        a.moved_dist = 0.0
        return nothing
    end
    m.grid[x + 1, y + 1] === nothing || throw(ArgumentError("site ($x, $y) is occupied"))
    m.grid[a.x + 1, a.y + 1] = nothing
    m.grid[x + 1, y + 1] = a
    w, h = m.config.width, m.config.height
    dx = mod(x - a.x + w ÷ 2, w) - w ÷ 2  # shortest way round the torus
    dy = mod(y - a.y + h ÷ 2, h) - h ÷ 2
    a.disp_x += dx
    a.disp_y += dy
    # xxl's travel cost and movement metric read the distance (torus_dist from the same offsets); the book never does
    m.config.xxl === nothing || (a.moved_dist = sqrt(Float64(dx * dx + dy * dy)))
    a.x, a.y = x, y
    return nothing
end

function kill!(m::Model, a::Agent)
    a.alive = false
    m.grid[a.x + 1, a.y + 1] = nothing
    last = pop!(m.agents)  # swap-remove: the order of m.agents carries no meaning
    if last !== a
        m.agents[a.slot] = last
        last.slot = a.slot
    end
    a.slot = 0
    push!(m.dead_this_step, a)
    return nothing
end

deaths_this_step(m::Model) = length(m.dead_this_step)

"""Every agent created so far, living or dead (ids are issued in sequence)."""
agents_ever(m::Model) = m.next_id

"""
    die!(m, a; excluded_heirs=(), loans=true)

Every death goes through here: loans (rule L), inheritance I (p.67) when enabled, then removal. The positive part of
the agent's wealth is split equally among its living children, skipping `excluded_heirs` (agents dying in the same
batch; Kehoe's reading). `loans=false` when the caller has already settled the agent's loans (`credit_on_deaths!`).
"""
function die!(m::Model, a::Agent; excluded_heirs=(), loans::Bool=true)
    loans && !isempty(m.loans) && credit_on_death!(m, a, excluded_heirs)
    if m.config.inheritance
        heirs = [c for c in a.children if c.alive && !(c in excluded_heirs)]
        for heir in heirs
            a.sugar > 0 && (heir.sugar += a.sugar / length(heirs))
            a.spice > 0 && (heir.spice += a.spice / length(heirs))
        end
    end
    kill!(m, a)
    return nothing
end

# --- time ----------------------------------------------------------------------------

"""
    step!(m)

One period, in the order fixed by the design (Model.step): agents act one at a time in a fresh random order; then
aging and old-age death, loan settlement, replacement, growback (or seasons), and diffusion.
"""
function step!(m::Model)
    cfg = m.config
    empty!(m.dead_this_step)
    isempty(m.killed) || empty!(m.killed)
    empty!(m.trade_log)
    empty!(m.infection_log)
    for a in m.agents
        a.moved = false
    end

    # Agents act one at a time in a fresh random order each period (p.26).
    order = m.order
    resize!(order, length(m.agents))
    copyto!(order, m.agents)
    shuffle!(m.rng, order)
    for a in order
        a.alive || continue
        if cfg.combat_alpha !== nothing
            combat_move!(m, a)
        else
            move!(m, a)
        end
        metabolize!(m, a)
        a.alive || continue
        set_neighbors!(m, a)
        xxl_on(cfg, :word_of_mouth) && word_of_mouth!(m, a)  # xxl rule 3
        # The rules below look up neighbours afresh, as Python does: a child born in rule S is already a neighbour
        # for K, T, L and E, but not in `a.neighbors`, which friendship (and the metrics) read.
        cfg.sex && mate!(m, a)
        if cfg.culture
            culture_transmit!(m, a)
            update_friends!(a, a.neighbors)
        end
        cfg.trade && trade_with_neighbors!(m, a)
        cfg.credit !== nothing && seek_credit!(m, a)
        if cfg.disease_list > 0
            # E: transmission, then immune response (design, Scheduling).
            disease_transmit!(m, a)
            immune_response!(m, a)
        end
    end
    empty!(order)

    # End of period: aging and old-age death, replacement, then the environment.
    for a in m.agents
        a.age += 1
    end
    # In creation order, as Python's agent list keeps them (design, "Free to differ"): m.agents is not.
    dying = sort!([a for a in m.agents if a.age >= a.max_age]; by=a -> a.id)
    if !isempty(dying)
        batch = Set{Agent}(dying)  # identity: Agent is mutable
        # The batch's loans in one pass: the same book as one death at a time, since heirs are never in the batch and
        # nothing in between reads loans.
        isempty(m.loans) || credit_on_deaths!(m, batch, batch)
        for a in dying
            die!(m, a; excluded_heirs=batch, loans=false)
        end
    end
    cfg.credit !== nothing && settle_loans!(m)
    if cfg.replacement
        for dead in copy(m.dead_this_step)
            spawn_random_agent!(m; tribe=cfg.replacement_same_tribe ? tribe(dead) : :none)
        end
    end

    ls = m.landscape
    if cfg.seasons !== nothing
        beta, gamma = cfg.seasons
        if xxl_on(cfg, :gradient)
            seasonal_growback_gradient!(ls, m.t, cfg.growback_rate, beta, gamma)
        else
            seasonal_growback!(ls, m.t, cfg.growback_rate, beta, gamma, cfg.winter_growback)
        end
    else
        growback!(ls, cfg.growback_rate)
    end
    period = cfg.diffusion_period
    if period !== nothing && m.t >= cfg.diffusion_start && mod(m.t, period) == 0
        for _ in 1:(cfg.diffusion_passes)
            diffuse!(ls)
        end
    end
    m.t += 1
    return m
end

function set_neighbors!(m::Model, a::Agent)
    xxl_on(m.config, :radius) && return radius_neighbors!(a.neighbors, m, a)
    empty!(a.neighbors)
    for (dx, dy) in VON_NEUMANN
        other = agent_at(m, a.x + dx, a.y + dy)
        other === nothing || push!(a.neighbors, other)
    end
    return a.neighbors
end

function run!(m::Model, steps::Int; observer=nothing)
    observer === nothing || observer(m)
    for _ in 1:steps
        step!(m)
        observer === nothing || observer(m)
    end
    return m
end

# --- setup ---------------------------------------------------------------------------

"""`k` distinct values of 1:n, uniformly at random, in random order (partial Fisher-Yates)."""
function sample_distinct(rng::AbstractRNG, n::Int, k::Int)
    0 <= k <= n || throw(ArgumentError("cannot draw $k distinct values from $n"))
    v = collect(1:n)
    @inbounds for i in 1:k
        j = rand(rng, i:n)
        v[i], v[j] = v[j], v[i]
    end
    return resize!(v, k)
end

draw(rng::AbstractRNG, bounds::Tuple{Int,Int}) = rand(rng, bounds[1]:bounds[2])

function place_initial_population!(m::Model)
    cfg = m.config
    if !isempty(cfg.initial_blocks)
        place_blocks!(m)
        return nothing
    end
    if cfg.placement == "block"
        x0, y0, w, h = cfg.block
        sites = [wrap(m, x0 + i, y0 + j) for i in 0:(w - 1) for j in 0:(h - 1)]
    else
        sites = [(x, y) for x in 0:(cfg.width - 1) for y in 0:(cfg.height - 1)]
    end
    n = cfg.initial_population
    n > length(sites) && throw(
        ArgumentError("$n agents do not fit in $(length(sites)) $(cfg.placement) sites")
    )
    if xxl_on(cfg, :viable)  # xxl: each founder's traits first, then a site that feeds it (xxl/placement.jl)
        if cfg.placement == "block"
            place_viable!(
                m, site_indices(m, sites), Dict{Tuple{Int,Int},Vector{Int32}}(), n
            )
        else
            place_viable!(m, grid_sites(m), m.viable_sites, n)  # shares the grid's lists with rule R
        end
        return nothing
    end
    for i in sample_distinct(m.rng, length(sites), n)
        spawn_at!(m, sites[i]...)
    end
    return nothing
end

"""
    spawn_at!(m, x, y; tribe=:none)

A founder or newcomer with random genetics, endowment and max age (Model._spawn_at). Later chapters' draws come after
earlier ones and only when their rules are on, as in Python.
"""
function spawn_at!(m::Model, x::Int, y::Int; tribe::Symbol=:none)
    vision, metabolism, sugar, max_age = spawn_chapter2_draws(m)
    a = new_agent!(m, x, y, vision, metabolism, sugar; max_age=max_age)
    spawn_chapter_draws!(m, a, tribe)
    return a
end

"""Chapter II draws for a new random agent, in Python's order: vision, metabolism, endowment, max age."""
function spawn_chapter2_draws(m::Model)
    cfg, rng = m.config, m.rng
    s = cfg.look_stride  # 1 except in xl, where vision is drawn in whole strides: 10, 20, ...
    vision = s * draw(rng, (cfg.vision[1] ÷ s, cfg.vision[2] ÷ s))
    metabolism = draw(rng, capped_range(cfg, cfg.metabolism))
    sugar = draw(rng, cfg.endowment)
    max_age = cfg.max_age === nothing ? Inf : Float64(draw(rng, cfg.max_age))
    return vision, metabolism, sugar, max_age
end

"""Chapter III-V draws for a new random agent, each gated by its rules and in Python's order (III, IV, V), then xxl's speed."""
function spawn_chapter_draws!(m::Model, a::Agent, tribe::Symbol)
    cfg, rng = m.config, m.rng
    # Chapter III draws come after the Chapter II ones.
    if cfg.tag_length > 0
        a.tags, a.ntags = random_tags(rng, cfg.tag_length, tribe), cfg.tag_length
    end
    cfg.sex && assign_sex!(m, a, random_sex(rng))
    # Chapter IV draws come after those.
    if cfg.spice
        a.spice_metabolism = draw(rng, capped_range(cfg, cfg.spice_metabolism))
        a.spice =
            a.initial_spice = Float64(
                draw(rng, something(cfg.spice_endowment, cfg.endowment))
            )
        cfg.foresight === nothing || (a.foresight = draw(rng, cfg.foresight))
    end
    # Chapter V draws come last.
    if cfg.disease_list > 0
        a.immune_genotype = rand(rng, UInt64) & tag_mask(cfg.immune_length)
        a.immune, a.nimmune = a.immune_genotype, cfg.immune_length  # the phenotype trains on a copy (p.146)
        a.disease_fee = cfg.disease_fee
    end
    # xxl's draws come after every book draw.
    xxl_on(cfg, :speed) && (a.speed = draw(rng, cfg.xxl.speed))
    return a
end

"""Tribal blocks (Config.initial_blocks): each block's agents at distinct random empty sites inside it."""
function place_blocks!(m::Model)
    for (name, x0, y0, w, h, n) in m.config.initial_blocks
        sites = [
            (x0 + i, y0 + j) for i in 0:(w - 1) for
            j in 0:(h - 1) if m.grid[x0 + i + 1, y0 + j + 1] === nothing
        ]
        n > length(sites) && throw(
            ArgumentError(
                "$n $name agents do not fit in $(length(sites)) empty block sites"
            ),
        )
        if xxl_on(m.config, :viable)  # xxl: the viable rule within the block (xxl/placement.jl)
            cache = Dict{Tuple{Int,Int},Vector{Int32}}()
            place_viable!(m, site_indices(m, sites), cache, n; tribe=Symbol(name))
            continue
        end
        for i in sample_distinct(m.rng, length(sites), n)
            spawn_at!(m, sites[i]...; tribe=Symbol(name))
        end
    end
    return nothing
end
