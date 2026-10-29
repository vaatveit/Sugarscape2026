# Population statistics and the per-period metrics the runner records (sugarscape/stats.py), in the Python runner's
# column order: standard (Chapter II), society (III), economic (IV), disease (V).

const METRIC_COLUMNS = [
    # standard_metrics
    "population",
    "mean_vision",
    "mean_metabolism",
    "mean_sugar",
    "gini",
    "mean_neighbors",
    "moved",
    "ne_fraction",
    "on_peak_fraction",
    "north_frac_high_vision",
    "north_frac_low_vision",
    "summer_north",
    # society_metrics
    "n_blue",
    "n_red",
    "blue_fraction",
    "sw_blue",
    "sw_red",
    "ne_blue",
    "ne_red",
    "blue_xy",
    "red_xy",
    "blue_advance",
    "red_advance",
    "mean_children",
    "best_friend_closeness",
    "friend_closeness",
    "agents_ever",
    # economic_metrics
    "mean_spice",
    "trades",
    "mean_price",
    "mean_log_price",
    "price_sd",
    "sugar_traded",
    "spice_traded",
    "mean_foresight",
    "n_loans",
    "n_lenders",
    "n_borrowers",
    "n_both",
    "credit_depth",
    # disease_metrics
    "mean_diseases",
    "sd_diseases",
    "fraction_sick",
    "new_infections",
    "diseases_circulating",
]

"""Group membership (p.73): blue when 0s outnumber 1s, red otherwise; `:none` without tags."""
function tribe(a::Agent)
    a.ntags == 0 && return :none
    return 2 * count_ones(a.tags) < a.ntags ? :blue : :red
end

"""Fraction of matching tags: 1 - Hamming distance / length."""
closeness(a::UInt64, b::UInt64, n::Int) = 1.0 - count_ones(a ⊻ b) / n

safe_mean(values) = isempty(values) ? NaN : sum(values) / length(values)

"""Population standard deviation (numpy's default), NaN when empty."""
function pop_std(values)
    isempty(values) && return NaN
    mu = sum(values) / length(values)
    return sqrt(sum(v -> (v - mu)^2, values) / length(values))
end

fraction(flags) = isempty(flags) ? NaN : count(flags) / length(flags)

"""Gini ratio sum|xi - xj| / (2 n^2 mean); NaN for an empty or zero-wealth population."""
function gini(values)
    x = sort!(Float64.(collect(values)))
    n = length(x)
    total = sum(x; init=0.0)
    (n == 0 || total == 0) && return NaN
    ranked = sum(i * x[i] for i in 1:n)
    return 2.0 * ranked / (n * total) - (n + 1) / n
end

"""
    collect_metrics(m) -> Vector{Float64}

This period's metrics, aligned with `metric_columns(m.config)`: the 45 of `METRIC_COLUMNS`, defined as in sugarscape/stats.py,
then the nine of `XXL_METRIC_COLUMNS` (`xxl_metrics!`) when the config has xxl rules.
"""
function collect_metrics(m::Model)
    out = Float64[]
    sizehint!(out, length(METRIC_COLUMNS) + length(XXL_METRIC_COLUMNS))
    standard_metrics!(out, m)
    society_metrics!(out, m)
    economic_metrics!(out, m)
    disease_metrics!(out, m)
    m.config.xxl === nothing || xxl_metrics!(out, m)
    return out
end

function standard_metrics!(out, m::Model)
    agents, cfg, ls = m.agents, m.config, m.landscape
    half_w, half_h = cfg.width ÷ 2, cfg.height ÷ 2
    high = [a for a in agents if a.vision >= 5]
    low = [a for a in agents if a.vision <= 2]
    summer_north =
        cfg.seasons === nothing ? NaN : (is_summer_north(m.t, cfg.seasons[2]) ? 1.0 : 0.0)
    push!(
        out,
        length(agents),
        safe_mean([a.vision for a in agents]),
        safe_mean([a.metabolism for a in agents]),
        safe_mean([a.sugar for a in agents]),
        gini([a.sugar + a.spice for a in agents]),  # spice is 0.0 on the sugar-only landscape
        safe_mean([length(a.neighbors) for a in agents]),
        count(a -> a.moved, agents),
        fraction([a.x >= half_w && a.y >= half_h for a in agents]),
        fraction([ls.capacity[a.x + 1, a.y + 1] >= 3 for a in agents]),
        fraction([a.y >= half_h for a in high]),
        fraction([a.y >= half_h for a in low]),
        summer_north,
    )
    return out
end

"""Chapter III: tribes (p.73), genealogy (p.68), friends (p.79). SW of the anti-diagonal when x + y < width."""
function society_metrics!(out, m::Model)
    agents, width = m.agents, m.config.width
    blue = [a for a in agents if tribe(a) === :blue]
    red = [a for a in agents if tribe(a) === :red]
    tagged = length(blue) + length(red)
    side(group, sw) = count(a -> (a.x + a.y < width) == sw, group)
    best, mean_close = Float64[], Float64[]
    for a in agents
        a.ntags == 0 && continue
        friends = [f for (f, _) in a.friends if f.alive && f.ntags > 0]
        isempty(friends) && continue
        scores = [closeness(a.tags, f.tags, a.ntags) for f in friends]
        push!(best, maximum(scores))
        push!(mean_close, sum(scores) / length(scores))
    end
    push!(
        out,
        length(blue),
        length(red),
        tagged == 0 ? NaN : length(blue) / tagged,
        side(blue, true),
        side(red, true),
        side(blue, false),
        side(red, false),
        safe_mean([a.x + a.y for a in blue]),
        safe_mean([a.x + a.y for a in red]),
        # Mean NE-ward travel since birth (disp_x + disp_y), immune to wrapping across the edges.
        safe_mean([a.disp_x + a.disp_y for a in blue]),
        safe_mean([a.disp_x + a.disp_y for a in red]),
        isempty(agents) ? 0.0 : safe_mean([length(a.children) for a in agents]),
        safe_mean(best),
        safe_mean(mean_close),
        agents_ever(m),  # p.64 fn 10 counts every agent that lived
    )
    return out
end

"""Longest lender -> borrower path (in loans) through the credit network; cycle-safe (`_longest_chain`)."""
function longest_chain(edges::Dict{Int,Vector{Int}})
    on_path = Set{Int}()
    function walk(node)
        best = 0
        for nxt in get(edges, node, Int[])
            nxt in on_path && continue
            push!(on_path, nxt)
            best = max(best, 1 + walk(nxt))
            delete!(on_path, nxt)
        end
        return best
    end
    best = 0
    for n in keys(edges)
        push!(on_path, n)
        best = max(best, walk(n))
        delete!(on_path, n)
    end
    return best
end

"""Chapter IV: trade prices and volume (pp.108-110), foresight (p.129), credit (p.133)."""
function economic_metrics!(out, m::Model)
    agents = m.agents
    log_prices = [log(d.price) for d in m.trade_log]
    lenders = Set(loan.lender.id for loan in m.loans)
    borrowers = Set(loan.borrower.id for loan in m.loans)
    edges = Dict{Int,Vector{Int}}()
    for loan in m.loans
        targets = get!(edges, loan.lender.id, Int[])
        loan.borrower.id in targets || push!(targets, loan.borrower.id)
    end
    mean_log = safe_mean(log_prices)
    push!(
        out,
        safe_mean([a.spice for a in agents]),
        length(log_prices),
        isempty(log_prices) ? NaN : exp(mean_log),
        mean_log,
        pop_std(log_prices),
        sum(d.sugar for d in m.trade_log; init=0.0),
        sum(d.spice for d in m.trade_log; init=0.0),
        safe_mean([a.foresight for a in agents]),
        length(m.loans),
        length(lenders),
        length(borrowers),
        length(intersect(lenders, borrowers)),
        longest_chain(edges),
    )
    return out
end

"""Chapter V: active diseases per agent (mean and SD), the share sick (p.147), new infections (p.150)."""
function disease_metrics!(out, m::Model)
    counts = [length(a.diseases) for a in m.agents]
    circulating = Set{Int}()
    for a in m.agents
        union!(circulating, a.diseases)
    end
    push!(
        out,
        safe_mean(counts),
        pop_std(counts),
        fraction([c > 0 for c in counts]),
        length(m.infection_log),
        length(circulating),
    )
    return out
end
