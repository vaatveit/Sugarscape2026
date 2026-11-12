# The codes a frame carries for each agent and cell, and the legend the page draws them with. Pure functions of one agent
# or one model; nothing here changes a model.

using Sugarscape: Agent, Model, Config, tribe, rich_cut

"""The colour modes of the map, in the order of the page's selector."""
const COLOUR_MODES = ["tribe", "culture", "wealth", "disease", "credit"]

"""Wealth band edges (sugar + spice): band 0 is below the first edge, band b is `EDGES[b] <= w < EDGES[b+1]`, band 8 the last."""
const WEALTH_EDGES = (1.0, 3.0, 10.0, 30.0, 100.0, 300.0, 1000.0, 3000.0)

"""Disease steps: the smallest disease count of each step 0 to 5."""
const DISEASE_STEPS = (0, 1, 2, 3, 5, 8)

"""`wealth_band(w)`: 0 to 8, see [`WEALTH_EDGES`](@ref)."""
function wealth_band(w::Real)::UInt8
    b = 0
    for edge in WEALTH_EDGES
        w >= edge || break
        b += 1
    end
    return UInt8(b)
end

"""`disease_step(n)`: 0 to 5 for 0, 1, 2, 3 to 4, 5 to 7 and 8 or more diseases."""
function disease_step(n::Integer)::UInt8
    s = 0
    for (i, from) in enumerate(DISEASE_STEPS)
        n >= from && (s = i - 1)
    end
    return UInt8(s)
end

"""
`tribe_code(a)`: 0 for blue, 1 for red. An agent without tags (`tribe` `:none`) would get 0 here, though the readings
count it in neither tribe; it cannot occur in the viewer, whose VI-1 experiments always give agents 11 tags.
"""
tribe_code(a::Agent)::UInt8 = tribe(a) === :red ? 0x01 : 0x00

"""Pollution band edges: band 0 is no pollution at all, band 1 above 0 and below the first edge, band b + 1 is
`EDGES[b] <= p < EDGES[b+1]`, band 8 the last edge or more."""
const POLLUTION_EDGES = (1.0, 3.0, 10.0, 30.0, 100.0, 300.0, 1000.0)

"""
`pollution_band(p)`: 0 to 8, see [`POLLUTION_EDGES`](@ref); throws for a negative or NaN level, which the model never
makes.
"""
function pollution_band(p::Real)::UInt8
    (p >= 0) || error("pollution $p is neither 0 nor positive")
    p == 0 && return 0x00
    b = 1
    for edge in POLLUTION_EDGES
        p >= edge || break
        b += 1
    end
    return UInt8(b)
end

"""`culture_ones(a)`: how many of the agent's tags are 1."""
culture_ones(a::Agent)::UInt8 = UInt8(count_ones(a.tags))

const ROLE_NONE, ROLE_LENDER, ROLE_BORROWER, ROLE_BOTH = 0x00, 0x01, 0x02, 0x03

"""`credit_roles(m)`: the role of each agent in an active loan, by id; agents in no loan are absent."""
function credit_roles(m::Model)::Dict{Int,UInt8}
    roles = Dict{Int,UInt8}()
    for l in m.loans
        roles[l.lender.id] = get(roles, l.lender.id, ROLE_NONE) | ROLE_LENDER
        roles[l.borrower.id] = get(roles, l.borrower.id, ROLE_NONE) | ROLE_BORROWER
    end
    return roles
end

"""`cell_eighths(level)`: a resource level in eighths, 0 to 255; throws when the level is not a whole number of eighths in range."""
function cell_eighths(level::Real)::UInt8
    e = 8 * level
    (isfinite(e) && e == round(e) && 0 <= e <= 255) ||
        error("cell level $level cannot be shown exactly in eighths (0 to 255)")
    return UInt8(e)
end

hexcolour(rgb) = "#" * join((string(round(Int, c); base=16, pad=2) for c in rgb), "")
mix(a, b, f) = ntuple(i -> a[i] + f * (b[i] - a[i]), 3)

function ramp(stops, n)
    n == 1 && return [hexcolour(stops[1])]
    return map(0:(n - 1)) do i
        p = i / (n - 1) * (length(stops) - 1)
        j = min(floor(Int, p), length(stops) - 2)
        hexcolour(mix(stops[j + 1], stops[j + 2], p - j))
    end
end

const BLUE_RGB = (37, 99, 235)
const RED_RGB = (192, 57, 43)

# White (clean) through a muted tan to a dark olive-brown. Every colour is at least 60 (RGB distance) from every agent
# colour of every mode and from the kill and switch mark colours, the closest being 68 from the wealth mode's dark
# purple-red (tested in julia/test/test_xxl_viewer_frame.jl and the page's tests). Greener than brown at the dark end,
# away from the dark wealth and disease reds; yellower than grey at mid-ramp, away from the credit and disease grey.
const POLLUTION_PALETTE = ["#ffffff", "#f7f1dc", "#e9dbb0", "#dbc585", "#c7b168", "#af9e54", "#958940", "#73732f",
    "#525c1e"]

# The pollution entry of the legend: `nothing` without pollution, else the bands, the start of pollution and of
# diffusion (`nothing` without diffusion), the rich land's cut and the share of cells it covers, and the decay rate
# (`pollution_decay`, 0 without decay).
function pollution_legend(m::Model)
    cfg = m.config
    cfg.pollution === nothing && return nothing
    ls = m.landscape
    cut = rich_cut(ls)
    labels = ["0 (clean)"; "below 1"; ["$(Int(POLLUTION_EDGES[b])) to < $(Int(POLLUTION_EDGES[b + 1]))" for b in 1:6];
        "1000 or more"]
    return Dict{String,Any}(
        "palette" => POLLUTION_PALETTE,
        "labels" => labels,
        "edges" => collect(POLLUTION_EDGES),
        "start" => cfg.pollution_start,
        "diffusion_start" => cfg.diffusion_period === nothing ? nothing : cfg.diffusion_start,
        "rich_cut" => cut,
        "rich_share" => count((ls.capacity .+ ls.spice_capacity) .>= cut) / length(ls.capacity),
        "decay" => cfg.pollution_decay,
    )
end

"""
    legend(m_or_cfg) -> Dict{String,Any}

What the page needs to draw and explain a frame: the modes, each mode's palette and labels, the band edges, the event
colours, the mark spacing, the largest resource capacity, the tag length, and `"pollution"`: `nothing` without
pollution, else its bands' palette, labels and edges, the periods pollution and diffusion start (`nothing` without
diffusion), the rich land's `rich_cut` and the share of cells it covers. A config builds a model to read its landscape.
"""
function legend(m::Model)
    ntags = m.config.tag_length
    wealth_labels = ["< 1"; ["$(Int(WEALTH_EDGES[b])) to < $(Int(WEALTH_EDGES[b + 1]))" for b in 1:7]; "3000 or more"]
    return Dict{String,Any}(
        "modes" => COLOUR_MODES,
        "palettes" => Dict(
            "tribe" => ["#2563eb", "#c0392b"],
            # Straight from the tribe blue to the tribe red through purple, no step lighter than its ends (mockup B).
            "culture" => ramp((BLUE_RGB, RED_RGB), ntags + 1),
            # Low to high, darkening; every agent colour stays at least 60 (RGB distance) from every landscape colour,
            # so it stands out on the pale landscape, and from the kill and switch mark colours, so a one-cell mark
            # never reads as an agent (both tested in julia/test/js/map.test.mjs). Hence no amber: the low wealth
            # bands start from coral and disease step 1 is coral, away from the switch mark's gold.
            "wealth" => ramp(((248, 113, 113), (234, 88, 12), (60, 10, 60)), 9),
            "disease" => ["#9ca3af", "#f87171", "#ea580c", "#dc2626", "#991b1b", "#450a0a"],
            "credit" => ["#9ca3af", "#16a34a", "#9333ea", "#0ea5e9"],
        ),
        "labels" => Dict(
            "tribe" => ["blue", "red"],
            "culture" => ["$k tags set" for k in 0:ntags],
            "wealth" => wealth_labels,
            "disease" => ["0 diseases", "1", "2", "3 to 4", "5 to 7", "8 or more"],
            "credit" => ["no loan", "lender", "borrower", "both"],
        ),
        "wealth_edges" => collect(WEALTH_EDGES),
        "disease_steps" => collect(DISEASE_STEPS),
        "kill_colour" => "#000000",
        "change_colour" => "#d4a000",
        "mark_periods" => 10,
        "max_level" => max(maximum(m.landscape.capacity; init=0), maximum(m.landscape.spice_capacity; init=0)),
        "ntags" => ntags,
        "pollution" => pollution_legend(m),
    )
end

legend(cfg::Config) = legend(Model(cfg))
