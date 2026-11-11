# The viewer's web server (HTTP.jl) and its background stepper. The stepper alone moves the run on; after each period
# it publishes the new frame and series values into the server's own copies, under one lock, so a request never reads
# the run while it steps and never waits for a period.

import HTTP

const STATIC_DIR = joinpath(@__DIR__, "static")

const CONTENT_TYPES = Dict(
    ".html" => "text/html; charset=utf-8",
    ".css" => "text/css; charset=utf-8",
    ".mjs" => "text/javascript; charset=utf-8",
    ".js" => "text/javascript; charset=utf-8",
    ".json" => "application/json; charset=utf-8",
    ".svg" => "image/svg+xml",
    ".png" => "image/png",
    ".ico" => "image/x-icon",
)

"""
    ViewerServer

A running viewer: the `HTTP.serve!` server and what its routes answer from. `lock` guards every field a request reads
(the run id, settings, state, error, the published `frames` and `series`, `newest`, `last_requested_t`); `control`
lets one start or stop happen at a time and is never taken by a request that only reads. `run` is moved on only by
[`step_once!`](@ref), never read by a request.
"""
mutable struct ViewerServer
    server::Any  # the HTTP.jl server
    lock::ReentrantLock
    control::ReentrantLock
    keep::Int
    autostep::Bool
    run::Union{Nothing,ViewerRun}
    run_id::Int  # 0 before any run
    settings::Union{Nothing,ViewerSettings}
    run_idx::Union{Nothing,Int}
    legend_json::Union{Nothing,String}  # the current run's legend
    default_legend_json::Union{Nothing,String}  # the default experiment's, built on first request before any run
    experiments_json::String
    frames::Dict{Int,Vector{UInt8}}  # published: the run's newest `keep` frames, the same (never mutated) bytes
    series::Dict{String,Vector{Float64}}  # published: one value per period, period 0 first
    newest::Int
    last_requested_t::Int
    state::String  # "idle", "running", "waiting", "stopped", "extinct" or "failed"
    error::Union{Nothing,String}
    stop_requested::Bool
    stepper::Union{Nothing,Task}
end

struct BadRequest <: Exception
    msg::String
end

json_response(status::Int, x) = json_text_response(status, to_json(x))
json_text_response(status::Int, text::String) =
    HTTP.Response(status, ["Content-Type" => "application/json; charset=utf-8", "Cache-Control" => "no-store"], text)
error_response(status::Int, msg::AbstractString) = json_response(status, (error=msg,))

# Every route answers: a bad input is 400 with its message, anything else that throws is 500, and the server goes on.
function guarded(f)
    return function (req)
        try
            return f(req)
        catch e
            e isa BadRequest && return error_response(400, e.msg)
            return error_response(500, sprint(showerror, e))
        end
    end
end

query_params(req) = HTTP.queryparams(HTTP.URI(req.target).query)

function nonneg_int(params, name)
    v = get(params, name, nothing)
    v === nothing && throw(BadRequest("$name is missing"))
    n = tryparse(Int, v)
    (n === nothing || n < 0) && throw(BadRequest("$name must be an integer >= 0, not $(repr(v))"))
    return n
end

function number(params, name, default::Float64)
    haskey(params, name) || return default
    x = tryparse(Float64, params[name])
    x === nothing && throw(BadRequest("$name must be a number, not $(repr(params[name]))"))
    return x
end

settings_json(::Nothing) = nothing
settings_json(s::ViewerSettings) = (exp=s.exp_id, seed=s.seed, h=s.h, k=s.k)

function experiments_json()
    return to_json(map(VIEWER_EXPS) do id
        exp = viewer_experiment(id)
        d = viewer_defaults(id)
        (id=id, title=exp.title, seed=d.seed, h=d.h, k=d.k, seeds=exp.seeds)
    end)
end

"""
    start_viewer(; host="127.0.0.1", port=8765, autostep=true, keep=VIEWER_KEEP) -> ViewerServer

Serves the viewer at `host:port` (port 0 picks a free one: `HTTP.port(s.server)`). With `autostep`, each started run is
stepped by a background task until stopped, extinct or failed, at most `keep ÷ 2` periods ahead of the newest frame the
page asked for; without it, nothing steps a run but [`step_once!`](@ref). Stop it with [`stop_viewer`](@ref).
"""
function start_viewer(; host::AbstractString="127.0.0.1", port::Integer=8765, autostep::Bool=true,
    keep::Int=VIEWER_KEEP)
    keep >= 2 || throw(ArgumentError("keep must be at least 2, not $keep"))
    s = ViewerServer(nothing, ReentrantLock(), ReentrantLock(), keep, autostep, nothing, 0, nothing, nothing, nothing,
        nothing, experiments_json(), Dict{Int,Vector{UInt8}}(), Dict(k => Float64[] for k in SERIES_KEYS), 0, 0,
        "idle", nothing, false, nothing)
    router = HTTP.Router()
    route(method, path, f) = HTTP.register!(router, method, path, guarded(req -> f(s, req)))
    route("GET", "/", (s, req) -> static_response("index.html"))
    route("GET", "/static/{file}", (s, req) -> static_response(HTTP.getparam(req, "file")))
    route("GET", "/api/experiments", (s, req) -> json_text_response(200, s.experiments_json))
    route("GET", "/api/legend", legend_route)
    route("POST", "/api/start", start_route)
    route("POST", "/api/stop", stop_route)
    route("GET", "/api/status", (s, req) -> json_response(200, viewer_status(s)))
    route("GET", "/api/frame", frame_route)
    route("GET", "/api/series", series_route)
    s.server = HTTP.serve!(router, host, port)
    return s
end

"""`stop_viewer(s)`: stops the stepper (waiting for its period to end), then closes the server and its connections."""
function stop_viewer(s::ViewerServer)
    lock(() -> stop_stepper!(s), s.control)
    HTTP.forceclose(s.server)
    wait(s.server)
    return nothing
end

# Asks the stepper to stop and waits for it; a run that was not failed or extinct is then "stopped".
function stop_stepper!(s::ViewerServer)
    task = lock(s.lock) do
        s.stop_requested = true
        s.run_id > 0 && s.state in ("idle", "running", "waiting") && (s.state = "stopped")
        s.stepper
    end
    task === nothing || wait(task)
    s.stepper = nothing
    return nothing
end

"""
    step_once!(s) -> Bool

Moves the current run on one period with `advance!` and publishes its frame and series values. `false` when there is
no run, the run is failed or extinct, or the population was already 0. An exception marks the run "failed" with its
message, and it is never stepped again. Called by the background stepper only (or by tests, with `autostep=false`).
"""
function step_once!(s::ViewerServer)
    r, id = lock(s.lock) do
        s.state in ("failed", "extinct") ? (nothing, 0) : (s.run, s.run_id)
    end
    r === nothing && return false
    stepped = try
        advance!(r)
    catch e
        lock(s.lock) do
            s.run_id == id && (s.state = "failed"; s.error = sprint(showerror, e))
        end
        return false
    end
    lock(s.lock) do
        s.run_id == id || return
        if stepped
            t = r.model.t
            s.frames[t] = r.frames[t]
            delete!(s.frames, t - s.keep)
            for k in SERIES_KEYS
                push!(s.series[k], r.series[k][end])
            end
            s.newest = t
        end
        isempty(r.model.agents) && (s.state = "extinct")
    end
    return stepped
end

# The background stepper of run `id`: steps while the run is current and neither stopped, failed nor extinct, waiting
# (re-checking every 0.05 s) while it is `keep ÷ 2` or more periods ahead of the newest frame the page asked for. It
# yields between periods so the server's tasks run on a single thread too.
function stepper_loop(s::ViewerServer, id::Int)
    try
        while true
            action = lock(s.lock) do
                if s.run_id != id || s.stop_requested || s.state in ("failed", "extinct")
                    :quit
                elseif s.newest - s.last_requested_t >= s.keep ÷ 2
                    s.state = "waiting"
                    :wait
                else
                    s.state = "running"
                    :step
                end
            end
            action === :quit && return nothing
            if action === :wait
                sleep(0.05)
            else
                step_once!(s)
                yield()
            end
        end
    catch e
        lock(s.lock) do
            s.run_id == id && (s.state = "failed"; s.error = sprint(showerror, e))
        end
    end
    return nothing
end

function viewer_status(s::ViewerServer)
    return lock(s.lock) do
        none = s.run_id == 0
        (run=none ? nothing : s.run_id, settings=settings_json(s.settings), run_index=s.run_idx,
            newest=none ? nothing : s.newest, oldest_kept=isempty(s.frames) ? nothing : minimum(keys(s.frames)),
            state=s.state, error=s.error)
    end
end

function legend_route(s::ViewerServer, req)
    text = lock(() -> s.run_id == 0 ? s.default_legend_json : s.legend_json, s.lock)
    if text === nothing
        # Before any run: the default experiment's legend, which builds a whole model, so once.
        text = to_json(legend(viewer_config(viewer_defaults(DEFAULT_EXP))))
        lock(() -> s.default_legend_json = text, s.lock)
    end
    return json_text_response(200, text)
end

# Settings from the form, each missing field the experiment's own; the model's config checks then decide.
function start_settings(form)
    exp_id = get(form, "exp", DEFAULT_EXP)
    exp_id in VIEWER_EXPS || throw(BadRequest("experiment is one of $(join(VIEWER_EXPS, ", ")), not $(repr(exp_id))"))
    d = viewer_defaults(exp_id)
    seed = haskey(form, "seed") ? nonneg_int(form, "seed") : d.seed
    settings = ViewerSettings(exp_id, seed, number(form, "h", d.h), number(form, "k", d.k))
    try
        viewer_config(settings)
    catch e
        e isa ArgumentError && throw(BadRequest(e.msg))
        rethrow()
    end
    return settings
end

function start_route(s::ViewerServer, req)
    settings = start_settings(HTTP.queryparams(String(copy(req.body))))
    id, idx = lock(s.control) do
        stop_stepper!(s)
        lock(() -> s.run = nothing, s.lock)  # the old run's model goes before the new one is built
        r = ViewerRun(settings; keep=s.keep)
        legend_text = to_json(legend(r.model))
        idx = run_index(settings)
        id, state = lock(s.lock) do
            s.run = r
            s.run_id += 1
            s.settings = settings
            s.run_idx = idx
            s.legend_json = legend_text
            s.frames = copy(r.frames)
            s.series = Dict(k => copy(v) for (k, v) in r.series)
            s.newest = r.model.t
            s.last_requested_t = r.model.t
            s.error = nothing
            s.stop_requested = false
            s.state = isempty(r.model.agents) ? "extinct" : s.autostep ? "running" : "idle"
            s.run_id, s.state
        end
        state == "running" && (s.stepper = Threads.@spawn stepper_loop(s, id))
        id, idx
    end
    return json_response(200, (run=id, settings=settings_json(settings), run_index=idx))
end

function stop_route(s::ViewerServer, req)
    lock(() -> stop_stepper!(s), s.control)
    return json_response(200, viewer_status(s))
end

# `run` from the query: the current run's id, or `nothing` when it names another (or there is none).
function current_run(s::ViewerServer, params)
    run = nonneg_int(params, "run")
    return s.run_id > 0 && run == s.run_id ? run : nothing
end

function frame_route(s::ViewerServer, req)
    q = query_params(req)
    run, t = nonneg_int(q, "run"), nonneg_int(q, "t")
    bytes = lock(s.lock) do
        current_run(s, q) === nothing && return :stale
        b = get(s.frames, t, nothing)
        b === nothing || (s.last_requested_t = t)
        b
    end
    bytes === :stale && return error_response(409, "run $run is not the current run")
    bytes === nothing && return error_response(404, "frame $t is not kept")
    return HTTP.Response(200, ["Content-Type" => "application/octet-stream", "Cache-Control" => "no-store"], bytes)
end

function series_route(s::ViewerServer, req)
    q = query_params(req)
    run, from = nonneg_int(q, "run"), nonneg_int(q, "from")
    values = lock(s.lock) do
        current_run(s, q) === nothing && return nothing
        n = length(s.series["t"])
        Dict(k => v[(min(from, n) + 1):end] for (k, v) in s.series)
    end
    values === nothing && return error_response(409, "run $run is not the current run")
    return json_response(200, (run=run, t0=from, series=values))
end

# A file directly in STATIC_DIR, named exactly as listed there; anything else, including any name that is or decodes
# to a path, is 404.
function static_response(name::AbstractString)
    decoded = HTTP.unescapeuri(name)
    bad = isempty(name) || startswith(name, ".") || any(n -> occursin("..", n) || occursin('/', n) || occursin('\\', n),
        (name, decoded))
    if bad || !(name in readdir(STATIC_DIR)) || !isfile(joinpath(STATIC_DIR, name)) ||
       realpath(dirname(realpath(joinpath(STATIC_DIR, name)))) != realpath(STATIC_DIR)
        return error_response(404, "no such file")
    end
    type = get(CONTENT_TYPES, lowercase(splitext(name)[2]), "application/octet-stream")
    return HTTP.Response(200, ["Content-Type" => type, "Cache-Control" => "no-store"], read(joinpath(STATIC_DIR, name)))
end
