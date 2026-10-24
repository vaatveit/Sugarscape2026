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

mutable struct Model
    config::Config
    rng::Xoshiro
    landscape::Landscape
    grid::Matrix{Union{Nothing,Agent}}
    agents::Vector{Agent}  # the living, in no particular order (each period draws a fresh order)
    t::Int
    dead_this_step::Vector{Agent}
    trade_log::Vector{Exchange}  # this period's exchanges (rule T)
    loans::Vector{Loan}  # active loans (rule L), in creation order
    next_id::Int
    infection_log::Vector{Tuple{Agent,Agent}}  # this period's (source, target) infections
    disease_list::Vector{Int}  # the master list (p.147), as interned disease ids
    disease_bits::Vector{UInt64}  # interned diseases: bit string and length, by id
    disease_len::Vector{Int}
    disease_ids::Dict{Tuple{UInt64,Int},Int}
    order::Vector{Agent}  # scratch: this period's acting order
end

"""
    Model(cfg; capacity=nothing)

Builds the world and its founders as `Model.__init__` does, drawing in Python's gated order: the disease master
list, the founders (Chapter II draws, then III, IV, V as enabled), initial infections, then founder ages.
"""
function Model(cfg::Config; capacity::Union{Nothing,AbstractMatrix{<:Integer}}=nothing)
    validate(cfg)
    cap = capacity === nothing ? load_map(cfg.sugar_map) : Matrix{Int}(capacity)
    size(cap) == (cfg.width, cfg.height) ||
        throw(ArgumentError("capacity shape $(size(cap)) != ($(cfg.width), $(cfg.height))"))
    # Fig IV-1: spice mountains NW and SE, i.e. the sugar map mirrored east-west.
    ls = Landscape(cap, cfg.spice ? reverse(cap; dims=1) : nothing)
    m = Model(
        cfg,
        Xoshiro(cfg.seed),
        ls,
        fill!(Matrix{Union{Nothing,Agent}}(undef, cfg.width, cfg.height), nothing),
        Agent[],
        0,
        Agent[],
        Exchange[],
        Loan[],
        0,
        Tuple{Agent,Agent}[],
        Int[],
        UInt64[],
        Int[],
        Dict{Tuple{UInt64,Int},Int}(),
        Agent[],
    )
    cfg.disease_list > 0 && init_disease_list!(m)
    place_initial_population!(m)
    cfg.diseases_per_agent > 0 && infect_founders!(m)
    # Founders of a society with finite lives start at ages U[0, max age) (Config.founder_ages). Drawn last, and
    # only with finite lives.
    if cfg.max_age !== nothing && cfg.founder_ages == "uniform"
        for a in m.agents
            a.age = rand(m.rng, 0:(Int(a.max_age) - 1))
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

"""Living agents on the four von Neumann sites around `a` (p.39), in the order E, W, N, S."""
function neighbors_of(m::Model, a::Agent)
    found = Agent[]
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
    a = Agent(m.next_id, x, y, vision, metabolism, Float64(sugar), Float64(max_age))
    m.next_id += 1
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
    site = random_empty_site(m)
    site === nothing &&
        throw(ArgumentError("no empty site for a new agent: the lattice is full"))
    return spawn_at!(m, site...; tribe=tribe)
end

function move_agent!(m::Model, a::Agent, x::Int, y::Int)
    x, y = wrap(m, x, y)
    (x, y) == (a.x, a.y) && return nothing
    m.grid[x + 1, y + 1] === nothing || throw(ArgumentError("site ($x, $y) is occupied"))
    m.grid[a.x + 1, a.y + 1] = nothing
    m.grid[x + 1, y + 1] = a
    w, h = m.config.width, m.config.height
    a.disp_x += mod(x - a.x + w ÷ 2, w) - w ÷ 2  # shortest way round the torus
    a.disp_y += mod(y - a.y + h ÷ 2, h) - h ÷ 2
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
    die!(m, a; excluded_heirs=())

Every death goes through here: loans (rule L), inheritance I (p.67) when enabled, then removal. The positive part of
the agent's wealth is split equally among its living children, skipping `excluded_heirs` (agents dying in the same
batch; Kehoe's reading).
"""
function die!(m::Model, a::Agent; excluded_heirs=())
    isempty(m.loans) || credit_on_death!(m, a, excluded_heirs)
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
    dying = [a for a in m.agents if a.age >= a.max_age]
    if !isempty(dying)
        batch = Set{Agent}(dying)  # identity: Agent is mutable
        for a in dying
            die!(m, a; excluded_heirs=batch)
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
        seasonal_growback!(ls, m.t, cfg.growback_rate, beta, gamma, cfg.winter_growback)
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
    cfg, rng = m.config, m.rng
    vision = draw(rng, cfg.vision)
    metabolism = draw(rng, cfg.metabolism)
    sugar = draw(rng, cfg.endowment)
    max_age = cfg.max_age === nothing ? Inf : Float64(draw(rng, cfg.max_age))
    a = new_agent!(m, x, y, vision, metabolism, sugar; max_age=max_age)
    spawn_chapter_draws!(m, a, tribe)
    return a
end

"""Chapter III-V draws for a new random agent, each gated by its rules and in Python's order (III, IV, V)."""
function spawn_chapter_draws!(m::Model, a::Agent, tribe::Symbol)
    return a
end
