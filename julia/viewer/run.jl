# The viewer's run: one today-world seed of a VI-1 combat experiment, stepped as `timed_seed` steps a study seed (step!,
# then the combat readings, then the standard metrics; period 0 has no step), with each charted value taken from those
# readings and never recomputed.

using Sugarscape: Model, Config, Loan, CombatReadings, COMBAT_COLUMNS, JULIA_COMBAT_EXPS, world_config, replace_config,
    metric_columns, collect_metrics, combat_period!, step!

"""The experiments the viewer offers, in the order of its menu: the eight VI-1 ones of the combat study."""
const VIEWER_EXPS = [
    "VI-1-combat", "VI-1-distance", "VI-1-near", "VI-1-far", "VI-1-far-speed", "VI-1-assim", "VI-1-assim-random",
    "VI-1-assim-k4",
]

"""How many of the newest frames a run keeps."""
const VIEWER_KEEP = 100

const DEFAULT_EXP = "VI-1-assim-k4"

"""What a run is started from: the experiment, the raw seed, the hostility `h` (`combat_hostility`) and the curve `k` (`combat_curve`)."""
struct ViewerSettings
    exp_id::String
    seed::Int
    h::Float64
    k::Float64
end

function viewer_experiment(exp_id::AbstractString)
    exp_id in VIEWER_EXPS || throw(ArgumentError("experiment is one of $(join(VIEWER_EXPS, ", ")), not $(repr(exp_id))"))
    return JULIA_COMBAT_EXPS[exp_id]()
end

"""`viewer_defaults(exp_id)`: the experiment's base seed and its today-world h and k."""
function viewer_defaults(exp_id::AbstractString)
    cfg = world_config(viewer_experiment(exp_id), "today")
    return ViewerSettings(String(exp_id), cfg.seed, cfg.combat_hostility, cfg.combat_curve)
end

"""
    viewer_config(s) -> Config

The config of the combat study's today world for `s.exp_id`, with the raw seed `s.seed` and `s.h` and `s.k`. Throws
`ArgumentError` for an unknown experiment or a setting the config's checks refuse.
"""
function viewer_config(s::ViewerSettings)
    cfg = world_config(viewer_experiment(s.exp_id), "today")
    return replace_config(cfg; seed=s.seed, combat_hostility=s.h, combat_curve=s.k)
end

"""`run_index(s)`: `k` when `s.seed` is the experiment's base seed + `k` for one of its registered runs, else `nothing`."""
function run_index(s::ViewerSettings)
    exp = viewer_experiment(s.exp_id)
    k = s.seed - world_config(exp, "today").seed
    return 0 <= k < exp.seeds ? k : nothing
end

"""The series of a run, by key: `t` and the values the charts draw."""
const SERIES_KEYS = ["t", "population", "n_blue", "n_red", "killed_blue", "killed_red", "tribe_changes", "gini", "trades",
    "mean_price", "n_loans", "total_debt", "fraction_sick"]

const COMBAT_SERIES = ["population", "n_blue", "n_red", "killed_blue", "killed_red", "tribe_changes"]
const METRIC_SERIES = ["gini", "trades", "mean_price", "n_loans", "fraction_sick"]

"""The sum of what the active loans still owe."""
total_debt(m::Model) = sum(l.due for l in m.loans; init=0.0)

"""
    ViewerRun(s)

A run of `s`: its model (period 0 read, no step yet), the combat `readings`, `series` (one value per period for each of
[`SERIES_KEYS`](@ref), period 0 first) and `metric_rows`, each period's full metrics row in `metric_columns(model.config)`
order. `frames` holds each period's encoded frame, the newest `keep`. Move it on with [`advance!`](@ref).
"""
mutable struct ViewerRun
    settings::ViewerSettings
    model::Model
    readings::CombatReadings
    series::Dict{String,Vector{Float64}}
    metric_rows::Vector{Vector{Float64}}
    metric_index::Dict{String,Int}  # metric column name -> position in a metric row
    frames::Dict{Int,Vector{UInt8}}  # encoded frames by t, the newest `keep` only
    keep::Int
end

function ViewerRun(s::ViewerSettings; keep::Int=VIEWER_KEEP)
    m = Model(viewer_config(s))
    columns = metric_columns(m.config)
    r = ViewerRun(s, m, CombatReadings(), Dict(k => Float64[] for k in SERIES_KEYS), Vector{Float64}[],
        Dict(c => i for (i, c) in enumerate(columns)), Dict{Int,Vector{UInt8}}(), keep)
    keep_frame!(r)
    read_period!(r)
    return r
end

# The period's frame, taken before the readings overwrite the previous tribes it compares with.
function keep_frame!(r::ViewerRun)
    m = r.model
    r.frames[m.t] = encode_frame(capture_frame(m, r.readings.prev, r.readings.seen))
    delete!(r.frames, m.t - r.keep)
    return nothing
end

# The end of a period, as `timed_seed` reads it: the combat readings, then the metrics, once each; the series take their
# values from those rows.
function read_period!(r::ViewerRun)
    m = r.model
    combat_period!(r.readings, m)
    metrics = collect_metrics(m)
    push!(r.metric_rows, metrics)
    combat = r.readings.rows[end]
    push!(r.series["t"], m.t)
    for key in COMBAT_SERIES
        push!(r.series[key], combat[findfirst(==(key), COMBAT_COLUMNS)])
    end
    for key in METRIC_SERIES
        push!(r.series[key], metrics[r.metric_index[key]])
    end
    push!(r.series["total_debt"], total_debt(m))
    return nothing
end

"""
    advance!(r) -> Bool

One period: `step!`, the readings and the metrics. Returns `false`, changing nothing, when the population is already 0.
"""
function advance!(r::ViewerRun)
    isempty(r.model.agents) && return false
    step!(r.model)
    keep_frame!(r)
    read_period!(r)
    return true
end

"""`series_since(r, t0)`: each series' values for periods `t0` to the newest, as a new dictionary."""
function series_since(r::ViewerRun, t0::Int)
    return Dict(k => v[(t0 + 1):end] for (k, v) in r.series)
end
