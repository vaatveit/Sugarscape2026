# xxl (revised): viable founder placement (docs/superpowers/specs/2026-10-29-xxl-revised-design.md, "Stage 1:
# survival", change 2). A founder or rule-R newcomer draws its traits first, then its site: uniformly among the empty
# candidate sites that feed it, or, when none is free, uniformly among all empty candidates, counted as a fallback.
# Sites are linear grid indices here (x + 1 + y * width, as `m.grid[i]` reads them), held as Int32 to keep the cached
# lists small: the grid has a list for each pair that comes up, each up to 250,000 sites long.

const VIABLE_TRIES = 64  # rejection draws before an exact count, as in random_empty_site

"""
    viable(m, a, x, y) -> Bool

Whether site (x, y) feeds `a` from its own capacity: sugar capacity ≥ its sugar metabolism and, with spice, spice
capacity ≥ its spice metabolism (spec, "Stage 1: survival", change 2).
"""
function viable(m::Model, a::Agent, x::Int, y::Int)
    return feeds(m, metabolism_pair(m, a), x + 1 + y * m.config.width)
end

# The cache key for `a`: its metabolisms, with 0 for spice when the run has none (every site's spice capacity is ≥ 0).
function metabolism_pair(m::Model, a::Agent)
    return (a.metabolism, m.config.spice ? a.spice_metabolism : 0)
end

# Whether grid site `i` feeds the metabolism pair `p`. Without spice the spice capacities are 0 and p[2] is 0.
@inline function feeds(m::Model, p::Tuple{Int,Int}, i::Integer)
    ls = m.landscape
    return ls.capacity[i] >= p[1] && ls.spice_capacity[i] >= p[2]
end

"""Every site of the grid as a linear index, in grid order."""
grid_sites(m::Model) = Base.OneTo(Int32(length(m.grid)))

"""The 0-based sites `sites` as linear grid indices, wrapped onto the torus."""
function site_indices(m::Model, sites::AbstractVector{Tuple{Int,Int}})
    w = m.config.width
    return Int32[(xy=wrap(m, x, y); xy[1] + 1 + xy[2] * w) for (x, y) in sites]
end

"""
    spawn_viable!(m, sites; tribe=:none) -> Agent

A founder or newcomer with random genetics, endowment and max age, its traits drawn exactly as [`spawn_at!`](@ref)
draws them (vision, metabolism, endowment, max age, then `spawn_chapter_draws!` with xxl's speed last), and only then
placed: at a uniformly random empty site of `sites` that feeds it ([`viable`](@ref)), or, when none of those is
empty, at a uniformly random empty site of `sites`, counted in `m.viable_fallbacks` (spec, "Stage 1: survival",
change 2). Throws when no site of `sites` is empty.
"""
function spawn_viable!(m::Model, sites::AbstractVector{Tuple{Int,Int}}; tribe::Symbol=:none)
    return spawn_viable!(
        m, site_indices(m, sites), Dict{Tuple{Int,Int},Vector{Int32}}(); tribe=tribe
    )
end

# The work of spawn_viable! on candidates `cand` (linear grid indices). `cache` holds the candidates that feed each
# metabolism pair, built when the pair first comes up; it is valid for as long as `cand` and the capacities are, so the
# whole grid's (m.viable_sites) lasts the run. Only occupancy changes, and the draw reads it afresh.
function spawn_viable!(
    m::Model,
    cand::AbstractVector{<:Integer},
    cache::Dict{Tuple{Int,Int},Vector{Int32}};
    tribe::Symbol=:none,
)
    vision, metabolism, sugar, max_age = spawn_chapter2_draws(m)
    a = build_agent!(m, vision, metabolism, sugar; max_age=max_age)
    spawn_chapter_draws!(m, a, tribe)
    p = metabolism_pair(m, a)
    fed = get!(() -> Int32[i for i in cand if feeds(m, p, i)], cache, p)
    i = empty_site_among(m, fed)
    if i == 0
        i = empty_site_among(m, cand)
        i == 0 && throw(
            ArgumentError("no empty site for a new agent among $(length(cand)) sites")
        )
        m.viable_fallbacks += 1
    end
    w = m.config.width
    return place_agent!(m, a, (i - 1) % w, (i - 1) ÷ w)
end

"""`n` founders by [`spawn_viable!`](@ref) among the candidates `cand`, sharing `cache`."""
function place_viable!(
    m::Model,
    cand::AbstractVector{<:Integer},
    cache::Dict{Tuple{Int,Int},Vector{Int32}},
    n::Int;
    tribe::Symbol=:none,
)
    for _ in 1:n
        spawn_viable!(m, cand, cache; tribe=tribe)
    end
    return nothing
end

"""
A uniformly random empty site among the linear grid indices `list`, or 0 when every one is taken. Up to
`VIABLE_TRIES` rejection draws, then an exact count of the empty ones: each stage is uniform over the empty sites,
so the draw is, and a nearly full list costs one pass over it instead of an unbounded run of misses.
"""
function empty_site_among(m::Model, list::AbstractVector{<:Integer})
    n = length(list)
    n == 0 && return 0
    grid = m.grid
    for _ in 1:VIABLE_TRIES
        i = list[rand(m.rng, 1:n)]
        grid[i] === nothing && return Int(i)
    end
    empty = count(i -> grid[i] === nothing, list)
    empty == 0 && return 0
    k = rand(m.rng, 1:empty)
    for i in list
        if grid[i] === nothing
            k -= 1
            k == 0 && return Int(i)
        end
    end
    return 0  # not reached: `empty` sites were counted
end
