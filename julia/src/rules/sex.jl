# Agent sex rule S (pp.55-57, App. B p.183; sugarscape/rules/sex.py).

const GIFT_CAP = 5.0  # Ascape's most a parent gives a child (child_gift="capped")

"""
    is_fertile(a, threshold=1.0)

Of childbearing age and holding at least the sugar it was endowed with at birth (p.55). The test is sugar only, also
on the sugar-and-spice landscape (user decision, 2026-10-21). `threshold` scales the requirement
(Config.fertility_threshold).
"""
function is_fertile(a::Agent, threshold::Float64=1.0)
    return a.alive &&
           a.sex !== :none &&
           a.fertility_start <= a.age < a.fertility_end &&
           a.sugar >= threshold * a.initial_sugar
end

"""Sex and childbearing ages, each a random value in the stated range (p.57 fn 4)."""
function assign_sex!(m::Model, a::Agent, sex::Symbol)
    cfg = m.config
    a.sex = sex
    a.fertility_start = draw(m.rng, cfg.fertility_start)
    a.fertility_end = draw(
        m.rng, sex === :F ? cfg.female_fertility_end : cfg.male_fertility_end
    )
    return a
end

random_sex(rng::AbstractRNG) = rand(rng, 0:1) == 0 ? :F : :M

"""
The agents `a` may mate with: [`in_sight`](@ref) under mate_contact="vision", else [`neighbors_of`](@ref). The
scorecard's X2 counts mates in the same reach.
"""
mate_reach(m::Model, a::Agent) = m.config.mate_contact == "vision" ? in_sight(m, a) : neighbors_of(m, a)

"""
Agents within the agent's vision along the four lattice directions, nearest first (mate_contact="vision"). Returns
`m.sight`, which the next call reuses.
"""
function in_sight(m::Model, a::Agent)
    xxl_on(m.config, :disc) && return disc_in_sight(m, a)  # xxl: a fresh round look
    stride = m.config.look_stride
    n = a.vision ÷ stride
    # Each look as 4 dist + (d - 1), kept sorted: nearest first, and at equal distance in VON_NEUMANN order. A
    # distance drawn twice on one line is the same key, so it is looked at once (look_distances).
    looks = resize!(m.looks, 4n)
    len = 0
    for d in 1:4, k in 1:n  # each direction draws its own looks, line by line
        len = insert_sorted!(looks, len, 4 * look_distance(m.rng, stride, k) + d - 1)
    end
    found = empty!(m.sight)
    for i in 1:len
        dist, d = divrem(@inbounds(looks[i]), 4)
        dx, dy = @inbounds VON_NEUMANN[d + 1]
        other = agent_at(m, a.x + dx * dist, a.y + dy * dist)
        other === nothing || push!(found, other)
    end
    return found
end

"""
Adds the empty von Neumann sites around `a` not already listed (Python's dict.fromkeys order). Under xxl rule 4
(interaction radius R ≠ 1): the empty sites within R.
"""
function add_empty_sites!(sites::Vector{Tuple{Int,Int}}, m::Model, a::Agent)
    xxl_on(m.config, :radius) && return radius_empty_sites!(sites, m, a)
    for (dx, dy) in VON_NEUMANN
        s = wrap(m, a.x + dx, a.y + dy)
        m.grid[s[1] + 1, s[2] + 1] === nothing && !(s in sites) && push!(sites, s)
    end
    return sites
end

gift(v::Float64, down::Bool) = down ? floor(v) : v

"""
    mate!(m, a) -> children

Rule S: for each neighbour, in random order: if of the opposite sex, both fertile, and an empty site exists next to
either parent, a child is born there (p.56). Each parent gives half of its own initial endowment (p.55). The child
takes vision, metabolism and maximum age each from a random parent (Table III-1) and crossed tags (p.78); its sex is
a coin flip and its childbearing ages are drawn for its sex (our call). Placement among the empty sites is uniformly
random (our call). The labelled departures of Config (mate_contact, child_gift, child_threshold, gift_rounding) are
as in Python.
"""
function mate!(m::Model, a::Agent)
    rng, cfg = m.rng, m.config
    threshold, share = cfg.fertility_threshold, cfg.child_share
    capped, redraw = cfg.child_gift == "capped", cfg.child_threshold == "redraw"
    down = cfg.gift_rounding == "down"
    children = Agent[]
    partners = mate_reach(m, a)
    sites = m.sites
    for other in shuffle!(rng, partners)
        (other.sex === :none || other.sex === a.sex) && continue
        (is_fertile(a, threshold) && is_fertile(other, threshold)) || continue
        empty!(sites)
        add_empty_sites!(sites, m, a)
        add_empty_sites!(sites, m, other)
        isempty(sites) && continue
        x, y = sites[rand(rng, 1:length(sites))]
        parents = (a, other)
        vision = parents[rand(rng, 1:2)].vision
        metabolism = parents[rand(rng, 1:2)].metabolism
        max_age = parents[rand(rng, 1:2)].max_age
        g = map(
            p -> gift(
                capped ? min(GIFT_CAP, max(p.sugar, 0.0)) : p.initial_sugar * share,
                down,
            ),
            parents,
        )
        a.sugar -= g[1]
        other.sugar -= g[2]
        child = new_agent!(m, x, y, vision, metabolism, g[1] + g[2]; max_age=max_age)
        redraw && (child.initial_sugar = Float64(draw(rng, cfg.endowment)))
        assign_sex!(m, child, random_sex(rng))
        if a.ntags > 0 && other.ntags > 0
            child.tags, child.ntags = cross_tags(rng, a.tags, other.tags, a.ntags), a.ntags
        end
        if cfg.spice  # Chapter IV: draws come last so earlier streams are unchanged
            s = map(
                p -> gift(
                    capped ? min(GIFT_CAP, max(p.spice, 0.0)) : p.initial_spice * share,
                    down,
                ),
                parents,
            )
            a.spice -= s[1]
            other.spice -= s[2]
            child.spice = child.initial_spice = s[1] + s[2]
            redraw && (
                child.initial_spice = Float64(
                    draw(rng, something(cfg.spice_endowment, cfg.endowment))
                )
            )
            child.spice_metabolism = parents[rand(rng, 1:2)].spice_metabolism
            child.foresight = parents[rand(rng, 1:2)].foresight
        end
        if cfg.disease_list > 0  # Chapter V: untrained genotypes are crossed (p.146)
            child.immune_genotype = cross_tags(
                rng, a.immune_genotype, other.immune_genotype, a.nimmune
            )
            child.immune, child.nimmune = child.immune_genotype, a.nimmune
            child.disease_fee = cfg.disease_fee
        end
        xxl_on(cfg, :speed) && (child.speed = parents[rand(rng, 1:2)].speed)  # xxl: after every book draw
        push!(a.children, child)
        push!(other.children, child)
        push!(children, child)
    end
    return children
end
