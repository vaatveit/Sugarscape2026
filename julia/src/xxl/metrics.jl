# xxl: the nine added metrics (spec, "Metrics"). Appended to the 45 standard columns by `collect_metrics` when the config
# has xxl rules; `NaN` where a metric does not apply (no trade, no memory, no seasons, too few agents).

const XXL_METRIC_COLUMNS = [
    "mean_moved",
    "share_settled",
    "clustering_1",
    "clustering_10",
    "clustering_50",
    "regional_price_sd",
    "price_distance_slope",
    "share_remembered_target",
    "mean_winter_weight",
]

const CLUSTER_RADII = (1, 10, 50)  # the pair correlation's shells
const REGION_SIZE = 50  # regional prices: regions are 50 x 50 sites
const SLOPE_EXCHANGES = 2_000  # price_distance_slope reads this many of the period's exchanges, in log order

"""
    metric_columns(cfg) -> Vector{String}

The metric names, in order: the 45 of [`METRIC_COLUMNS`](@ref), then [`XXL_METRIC_COLUMNS`](@ref) for an xxl config.
"""
function metric_columns(cfg::Config)
    return cfg.xxl === nothing ? METRIC_COLUMNS : vcat(METRIC_COLUMNS, XXL_METRIC_COLUMNS)
end

"""
    shell_offsets(m, r) -> Vector{Tuple{Int,Int}}

Every distinct torus offset (dx, dy) with `r - 0.5 <= d < r + 0.5`, d = √(dx² + dy²) the torus distance, in the
integer form `r² - r + 1 <= dx² + dy² <= r² + r`. Cached on `m.near` under the key `-r`, which no disc radius uses.
"""
function shell_offsets(m::Model, r::Integer)
    return get!(m.near, -Float64(r)) do
        w, h = m.config.width, m.config.height
        function deltas(n)
            return [d for d in (torus_delta(n, 0, i) for i in 0:(n - 1)) if abs(d) <= r + 1]
        end
        offs = Tuple{Int,Int}[]
        for dx in deltas(w), dy in deltas(h)
            r * r - r + 1 <= dx * dx + dy * dy <= r * r + r && push!(offs, (dx, dy))
        end
        return offs
    end
end

"""
    shell_shares!(m) -> Vector{Float64}

P_r for each of `CLUSTER_RADII`: the share of ordered pairs of sugar-capacity >= 1 sites that lie at a shell-r offset
(`NaN` with fewer than two such sites). Computed on first use and cached in `m.shell_shares`; the capacities are fixed.
"""
function shell_shares!(m::Model)
    shares = m.shell_shares
    length(shares) == length(CLUSTER_RADII) && return shares
    cap, w, h = m.landscape.capacity, m.config.width, m.config.height
    sites = count(>=(1), cap)
    for r in CLUSTER_RADII
        if sites < 2
            push!(shares, NaN)
            continue
        end
        offs = shell_offsets(m, r)
        pairs = 0
        for y in 1:h, x in 1:w
            cap[x, y] >= 1 || continue
            for (dx, dy) in offs
                xx, yy = x + dx, y + dy
                xx < 1 && (xx += w)
                xx > w && (xx -= w)
                yy < 1 && (yy += h)
                yy > h && (yy -= h)
                pairs += cap[xx, yy] >= 1
            end
        end
        push!(shares, pairs / (sites * (sites - 1)))
    end
    return shares
end

"""
    clustering!(out, m)

Pushes the pair correlation at each of `CLUSTER_RADII`: the ordered pairs of agents at a shell-r offset, over what
N agents placed at random on the capacity >= 1 sites would give, N (N - 1) P_r. Above 1 is clustered. `NaN` with
fewer than two agents.
"""
function clustering!(out, m::Model)
    agents, grid = m.agents, m.grid
    n = length(agents)
    if n < 2
        for _ in CLUSTER_RADII
            push!(out, NaN)
        end
        return out
    end
    w, h = m.config.width, m.config.height
    shares = shell_shares!(m)
    for (i, r) in enumerate(CLUSTER_RADII)
        offs = shell_offsets(m, r)
        observed = 0
        for a in agents
            for (dx, dy) in offs
                xx, yy = a.x + 1 + dx, a.y + 1 + dy
                xx < 1 && (xx += w)
                xx > w && (xx -= w)
                yy < 1 && (yy += h)
                yy > h && (yy -= h)
                observed += grid[xx, yy] !== nothing
            end
        end
        push!(out, observed / (n * (n - 1) * shares[i]))
    end
    return out
end

"""
    regional_price_sd(m) -> Float64

The population sd of each region's mean log price, over the 50 x 50 regions holding at least one of this period's
exchanges (an exchange sits where its first agent is now). `NaN` without exchanges; 0 with one region.
"""
function regional_price_sd(m::Model)
    exchanges = m.trade_log
    isempty(exchanges) && return NaN
    nx = cld(m.config.width, REGION_SIZE)
    total = zeros(nx * cld(m.config.height, REGION_SIZE))
    tally = zeros(Int, length(total))
    for e in exchanges
        region = e.a.x ÷ REGION_SIZE + nx * (e.a.y ÷ REGION_SIZE) + 1
        total[region] += log(e.price)
        tally[region] += 1
    end
    return pop_std([total[i] / tally[i] for i in eachindex(total) if tally[i] > 0])
end

"""
    price_distance_slope(m) -> Float64

The least-squares slope of |Δ log price| on the torus distance between the first agents, over every unordered pair of
the period's first `SLOPE_EXCHANGES` exchanges. `NaN` with fewer than two exchanges or no spread in distance.
"""
function price_distance_slope(m::Model)
    exchanges = m.trade_log
    n = min(length(exchanges), SLOPE_EXCHANGES)
    n < 2 && return NaN
    w, h = m.config.width, m.config.height
    xs = [exchanges[i].a.x for i in 1:n]
    ys = [exchanges[i].a.y for i in 1:n]
    lp = [log(exchanges[i].price) for i in 1:n]
    pairs = 0
    sx = sy = sxx = sxy = 0.0
    for j in 2:n, i in 1:(j - 1)
        dx = abs(xs[i] - xs[j])
        dy = abs(ys[i] - ys[j])
        dx = min(dx, w - dx)
        dy = min(dy, h - dy)
        d = sqrt(Float64(dx * dx + dy * dy))
        dp = abs(lp[i] - lp[j])
        pairs += 1
        sx += d
        sy += dp
        sxx += d * d
        sxy += d * dp
    end
    spread = sxx - sx * sx / pairs
    spread <= 1e-9 * sxx && return NaN
    return (sxy - sx * sy / pairs) / spread
end

"""
    xxl_metrics!(out, m)

Pushes `XXL_METRIC_COLUMNS` in order. Movement and clustering always apply; the regional prices need exchanges, the
remembered share needs memory and the winter weight needs seasons.
"""
function xxl_metrics!(out, m::Model)
    agents, cfg = m.agents, m.config
    n = length(agents)
    push!(
        out,
        n == 0 ? NaN : sum(a.moved_dist for a in agents) / n,
        n == 0 ? NaN : count(a -> !a.moved, agents) / n,
    )
    clustering!(out, m)
    push!(
        out,
        regional_price_sd(m),
        price_distance_slope(m),
        xxl_on(cfg, :memory) && n > 0 ? count(a -> a.target_remembered, agents) / n : NaN,
        if cfg.seasons === nothing || n == 0
            NaN
        else
            sum(winter_weight(a.y, cfg.height) for a in agents) / n
        end,
    )
    return out
end
