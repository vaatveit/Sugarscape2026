# The xxl viewer's server (julia/viewer/json.jl, server.jl): the JSON writer, the routes, starting and replacing runs,
# the background stepper's backpressure and failure, and the static files' confinement.
isdefined(@__MODULE__, :XxlViewer) || include(joinpath(@__DIR__, "..", "viewer", "XxlViewer.jl"))
using Sugarscape, Test, HTTP
using .XxlViewer

const VS_ID = "VI-1-assim-k4"

# The test's own reader of the server's JSON: Dict, Vector{Any}, String, Float64, Bool or nothing.
function vs_json(text::AbstractString)
    b = codeunits(String(text))
    i = 1
    ws() = (while i <= length(b) && b[i] in (0x20, 0x09, 0x0a, 0x0d); i += 1; end)
    function expect(c)
        ws()
        @assert b[i] == UInt8(c) "expected $c at $i"
        i += 1
    end
    function str()
        expect('"')
        out = UInt8[]
        while b[i] != UInt8('"')
            if b[i] == UInt8('\\')
                e = Char(b[i + 1])
                if e == 'u'
                    append!(out, codeunits(string(Char(parse(UInt16, String(b[(i + 2):(i + 5)]); base=16)))))
                    i += 6
                    continue
                end
                push!(out, UInt8(Dict('"' => '"', '\\' => '\\', '/' => '/', 'n' => '\n', 't' => '\t', 'r' => '\r',
                    'b' => '\b', 'f' => '\f')[e]))
                i += 2
            else
                push!(out, b[i])
                i += 1
            end
        end
        i += 1
        return String(out)
    end
    function value()
        ws()
        c = Char(b[i])
        if c == '{'
            i += 1
            d = Dict{String,Any}()
            ws()
            b[i] == UInt8('}') && (i += 1; return d)
            while true
                k = str()
                expect(':')
                d[k] = value()
                ws()
                b[i] == UInt8(',') ? (i += 1) : (expect('}'); return d)
            end
        elseif c == '['
            i += 1
            v = Any[]
            ws()
            b[i] == UInt8(']') && (i += 1; return v)
            while true
                push!(v, value())
                ws()
                b[i] == UInt8(',') ? (i += 1) : (expect(']'); return v)
            end
        elseif c == '"'
            return str()
        else
            for (word, val) in (("null", nothing), ("true", true), ("false", false))
                if i + length(word) - 1 <= length(b) && String(b[i:(i + length(word) - 1)]) == word
                    i += length(word)
                    return val
                end
            end
            j = i
            while j <= length(b) && b[j] in codeunits("+-0123456789.eE")
                j += 1
            end
            x = parse(Float64, String(b[i:(j - 1)]))
            i = j
            return x
        end
    end
    v = value()
    ws()
    @assert i > length(b) "trailing text at $i"
    return v
end

vs_url(s, path) = "http://127.0.0.1:$(HTTP.port(s.server))$path"
vs_get(s, path) = HTTP.get(vs_url(s, path); status_exception=false, retry=false)
vs_post(s, path, form=Dict{String,String}()) = HTTP.post(vs_url(s, path), [], form; status_exception=false, retry=false)
vs_body(resp) = vs_json(String(copy(resp.body)))
vs_status(s) = vs_body(vs_get(s, "/api/status"))
vs_settings(x) = (x["exp"], x["seed"], x["h"], x["k"])
frame_t(bytes) = Int(only(reinterpret(Int32, bytes[5:8])))

# Waits until `f()` is true, polling every 0.1 s; false after `timeout` seconds.
function vs_until(f; timeout=300)
    t0 = time()
    while !f()
        time() - t0 > timeout && return false
        sleep(0.1)
    end
    return true
end

@testset "to_json" begin
    @test to_json((a=[1.0, NaN, 2.5], s="q\"\n", n=nothing, b=true)) == "{\"a\":[1,null,2.5],\"s\":\"q\\\"\\n\",\"n\":null,\"b\":true}"
    @test to_json([Inf, -Inf, 3, -0.5, 1e20, 1.0e-5]) == "[null,null,3,-0.5,1.0e20,1.0e-5]"
    @test to_json(Dict("b" => false, "a" => "x\\y\t\u01")) == "{\"a\":\"x\\\\y\\t\\u0001\",\"b\":false}"
    @test to_json(Any[]) == "[]"
    @test to_json(Dict{String,Any}()) == "{}"
    @test vs_json(to_json((u="Σ ≥ 1",))) == Dict("u" => "Σ ≥ 1")
end

@testset "experiments and index" begin
    s = start_viewer(; port=0, autostep=false)
    try
        resp = vs_get(s, "/api/experiments")
        @test resp.status == 200
        @test occursin("application/json", HTTP.header(resp, "Content-Type"))
        exps = vs_body(resp)
        @test [e["id"] for e in exps] == VIEWER_EXPS
        k4 = only(filter(e -> e["id"] == VS_ID, exps))
        d = viewer_defaults(VS_ID)
        @test (k4["seed"], k4["h"], k4["k"]) == (d.seed, d.h, d.k)
        @test k4["seeds"] > 0 && !isempty(k4["title"])
        @test (k4["steps"], k4["pollution"]) == (500, false)
        for id in ("VI-1-pollution", "VI-1-pollution-t0")
            e = only(filter(e -> e["id"] == id, exps))
            @test (e["steps"], e["pollution"]) == (600, true)
        end
        @test all(e -> e["pollution"] isa Bool, exps)

        page = vs_get(s, "/")
        @test page.status == 200
        @test occursin("text/html", HTTP.header(page, "Content-Type"))
        @test occursin("<canvas", String(copy(page.body)))

        st = vs_status(s)
        @test st["state"] == "idle"
        @test st["run"] === nothing && st["newest"] === nothing

        # Before any run: the default experiment's legend.
        lg = vs_body(vs_get(s, "/api/legend"))
        @test lg["modes"] == COLOUR_MODES && lg["max_level"] == 4

        @test vs_get(s, "/api/frame?run=1&t=0").status == 409
        @test vs_get(s, "/api/nothing-here").status == 404
    finally
        stop_viewer(s)
    end
end

@testset "a run's frames, series and failures" begin
    s = start_viewer(; port=0, autostep=false)
    try
        d = viewer_defaults(VS_ID)
        resp = vs_post(s, "/api/start", Dict("exp" => VS_ID, "seed" => string(d.seed), "h" => string(d.h),
            "k" => string(d.k)))
        @test resp.status == 200
        started = vs_body(resp)
        run = Int(started["run"])
        @test vs_settings(started["settings"]) == (VS_ID, d.seed, d.h, d.k)
        @test started["run_index"] == 0
        @test vs_status(s)["state"] == "idle"

        @testset "start, frame, series" begin
            @test step_once!(s)
            @test step_once!(s)
            st = vs_status(s)
            @test (st["run"], st["newest"], st["oldest_kept"], st["error"]) == (run, 2, 0, nothing)
            f = vs_get(s, "/api/frame?run=$run&t=2")
            @test f.status == 200
            @test HTTP.header(f, "Content-Type") == "application/octet-stream"
            @test String(f.body[1:4]) == "SXV2"
            @test frame_t(f.body) == 2
            @test vs_get(s, "/api/frame?run=$run&t=2").body == f.body  # serving shares the bytes, never alters them
            @test vs_get(s, "/api/frame?run=$run&t=3").status == 404
            ser = vs_body(vs_get(s, "/api/series?run=$run&from=0"))
            @test ser["run"] == run && ser["t0"] == 0
            @test sort(collect(keys(ser["series"]))) == sort(SERIES_KEYS)
            @test all(length(v) == 3 for v in values(ser["series"]))
            @test ser["series"]["t"] == [0, 1, 2]
            tail = vs_body(vs_get(s, "/api/series?run=$run&from=2"))
            @test tail["t0"] == 2 && tail["series"]["t"] == [2]
            lg = vs_body(vs_get(s, "/api/legend"))
            @test lg["max_level"] == 4 && length(lg["palettes"]["culture"]) == 12
        end

        @testset "series NaN is null" begin
            text = String(copy(vs_get(s, "/api/series?run=$run&from=0").body))
            m = match(r"\"mean_price\":\[([^\]]*)\]", text)
            @test m !== nothing
            @test split(m[1], ",")[1] == "null"
        end

        @testset "bad requests" begin
            for q in ("t=-1", "t=x", "t=1.5", "t=", "")
                @test vs_get(s, "/api/frame?run=$run&$q").status == 400
            end
            @test vs_get(s, "/api/frame?run=abc&t=0").status == 400
            @test vs_get(s, "/api/series?run=$run&from=-2").status == 400
            @test vs_get(s, "/api/series?run=$run").status == 400
            @test vs_get(s, "/api/series?run=$(run + 1)&from=0").status == 409
        end

        @testset "bad start keeps the run" begin
            for form in (Dict("exp" => "nope"), Dict("seed" => "-1"), Dict("seed" => "1.5"), Dict("h" => "x"),
                Dict("exp" => "VI-1-assim", "h" => "1"))
                resp = vs_post(s, "/api/start", form)
                @test resp.status == 400
                err = vs_body(resp)["error"]
                @test err isa String && !isempty(err)
                haskey(form, "exp") && form["exp"] == "VI-1-assim" && @test occursin("combat_hostility", err)
            end
            st = vs_status(s)
            @test st["run"] == run && st["newest"] == 2
            @test vs_get(s, "/api/frame?run=$run&t=2").status == 200
        end

        @testset "restart replaces the run" begin
            resp = vs_post(s, "/api/start", Dict("seed" => string(d.seed + 1)))
            @test resp.status == 200
            new = vs_body(resp)
            @test new["run"] != run && new["run_index"] == 1
            @test vs_settings(new["settings"]) == (VS_ID, d.seed + 1, d.h, d.k)
            @test vs_get(s, "/api/frame?run=$run&t=0").status == 409
            @test vs_get(s, "/api/series?run=$run&from=0").status == 409
            f = vs_get(s, "/api/frame?run=$(Int(new["run"]))&t=0")
            @test f.status == 200 && frame_t(f.body) == 0
            st = vs_status(s)
            @test (st["run"], st["newest"]) == (new["run"], 0)
            run = Int(new["run"])
        end

        @testset "an exception fails the run for good" begin
            # The metrics lookup breaks, so advance! throws after step!, leaving the model a period ahead.
            s.run.metric_index = Dict{String,Int}()
            @test !step_once!(s)
            st = vs_status(s)
            @test st["state"] == "failed"
            @test occursin("KeyError", st["error"])
            @test st["newest"] == 0
            t = s.run.model.t
            @test !step_once!(s)
            @test s.run.model.t == t
            @test vs_get(s, "/api/frame?run=$run&t=0").status == 200
        end
    finally
        stop_viewer(s)
    end
end

@testset "a pollution run publishes its pollution series and legend" begin
    s = start_viewer(; port=0, autostep=false)
    try
        resp = vs_post(s, "/api/start", Dict("exp" => "VI-1-pollution-t0"))
        @test resp.status == 200
        run = Int(vs_body(resp)["run"])
        @test step_once!(s)
        @test step_once!(s)
        ser = vs_body(vs_get(s, "/api/series?run=$run&from=0"))["series"]
        @test sort(collect(keys(ser))) == sort(series_keys(s.run.model.config))
        for key in POLLUTION_SERIES
            @test ser[key] == s.run.series[key]
        end
        lg = vs_body(vs_get(s, "/api/legend"))
        @test length(lg["pollution"]["palette"]) == 9 && lg["pollution"]["rich_cut"] == 5
    finally
        stop_viewer(s)
    end
end

@testset "the legend of a named run answers only while that run is current" begin
    # The page asks for its run's legend by id, so it never draws one run's frames with another run's legend.
    s = start_viewer(; port=0, autostep=false)
    try
        # Before any run: no run is current, and without `run` the default experiment's legend as before.
        @test vs_get(s, "/api/legend?run=1").status == 409
        @test vs_get(s, "/api/legend?run=0").status == 409
        default = vs_body(vs_get(s, "/api/legend"))
        @test default["pollution"] === nothing && default["max_level"] == 4

        a = Int(vs_body(vs_post(s, "/api/start", Dict("exp" => VS_ID)))["run"])
        la = vs_get(s, "/api/legend?run=$a")
        @test la.status == 200
        @test String(copy(la.body)) == String(copy(vs_get(s, "/api/legend").body))
        @test vs_body(la)["pollution"] === nothing
        @test vs_get(s, "/api/legend?run=$(a + 1)").status == 409
        @test vs_get(s, "/api/legend?run=abc").status == 400
        @test vs_get(s, "/api/legend?run=-1").status == 400

        b = Int(vs_body(vs_post(s, "/api/start", Dict("exp" => "VI-1-pollution-t0")))["run"])
        @test b != a
        stale = vs_get(s, "/api/legend?run=$a")
        @test stale.status == 409
        @test occursin("not the current run", vs_body(stale)["error"])
        lb = vs_get(s, "/api/legend?run=$b")
        @test lb.status == 200
        @test length(vs_body(lb)["pollution"]["palette"]) == 9
        # Without `run`: the current run's legend, as before.
        @test String(copy(vs_get(s, "/api/legend").body)) == String(copy(lb.body))
    finally
        stop_viewer(s)
    end
end

@testset "backpressure and stop" begin
    s = start_viewer(; port=0, autostep=true, keep=6)
    try
        run = Int(vs_body(vs_post(s, "/api/start"))["run"])
        task = s.stepper
        @test task isa Task && !istaskdone(task)
        @test vs_get(s, "/api/frame?run=$run&t=0").status == 200
        @test vs_until(() -> vs_status(s)["state"] == "waiting")
        @test vs_status(s)["newest"] == 3
        sleep(0.5)
        st = vs_status(s)
        @test (st["state"], st["newest"]) == ("waiting", 3)
        @test vs_get(s, "/api/frame?run=$run&t=3").status == 200
        @test vs_until(() -> vs_status(s)["newest"] > 3)
        @test vs_post(s, "/api/stop").status == 200
        @test istaskdone(task)
        st = vs_status(s)
        @test st["state"] == "stopped"
        newest = st["newest"]
        @test st["oldest_kept"] == max(0, newest - 5)
        sleep(0.3)
        @test vs_status(s)["newest"] == newest
        @test vs_get(s, "/api/frame?run=$run&t=$(Int(newest))").status == 200
        @test length(vs_body(vs_get(s, "/api/series?run=$run&from=0"))["series"]["t"]) == newest + 1
    finally
        stop_viewer(s)
    end
    @test !isopen(s.server)
end

@testset "the period shown moves the backpressure point" begin
    # The page shows frames from its own cache too, so it reports the period on the map with each status request: a
    # `shown` the server keeps moves the backpressure point exactly as a frame request does.
    s = start_viewer(; port=0, autostep=true, keep=6)
    try
        run = Int(vs_body(vs_post(s, "/api/start"))["run"])
        @test vs_until(() -> vs_status(s)["state"] == "waiting")
        @test vs_status(s)["newest"] == 3  # 3 ahead of period 0, the start's point
        # Ignored: another run's id, and a period the server does not keep.
        @test vs_get(s, "/api/status?run=$(run + 1)&shown=3").status == 200
        @test vs_get(s, "/api/status?run=$run&shown=50").status == 200
        sleep(0.5)
        st = vs_status(s)
        @test (st["state"], st["newest"]) == ("waiting", 3)
        @test s.last_requested_t == 0
        # Refused like `t`: not an integer >= 0, or without the run it belongs to.
        for q in ("run=$run&shown=-1", "run=$run&shown=x", "run=$run&shown=", "shown=3")
            @test vs_get(s, "/api/status?$q").status == 400
        end
        @test s.last_requested_t == 0
        # The shown period 3 is kept: the stepper resumes, up to 3 ahead of it.
        resp = vs_get(s, "/api/status?run=$run&shown=3")
        @test resp.status == 200
        @test vs_body(resp)["run"] == run
        @test vs_until(() -> (now = vs_status(s); now["state"] == "waiting" && now["newest"] == 6))
        @test s.last_requested_t == 3
        sleep(0.3)
        @test vs_status(s)["newest"] == 6
    finally
        stop_viewer(s)
    end
end

@testset "only the viewer's own host and origin" begin
    s = start_viewer(; port=0, autostep=false)
    try
        port = HTTP.port(s.server)
        get_as(path, host) = HTTP.get(vs_url(s, path), ["Host" => host]; status_exception=false, retry=false)
        post_from(path, origin, form=Dict{String,String}()) =
            HTTP.post(vs_url(s, path), ["Origin" => origin], form; status_exception=false, retry=false)
        # The page's own requests: Host 127.0.0.1:<port> (HTTP.jl's default here) or localhost:<port>.
        @test vs_get(s, "/").status == 200
        @test get_as("/api/status", "127.0.0.1:$port").status == 200
        @test get_as("/api/status", "localhost:$port").status == 200
        @test get_as("/static/style.css", "LOCALHOST:$port").status == 200  # host names are case-insensitive
        # Any other Host (DNS rebinding, another port, no port) is 403, on every route.
        for host in ("evil.example", "evil.example:$port", "127.0.0.1", "localhost", "127.0.0.1:$(port + 1)",
            "127.0.0.2:$port", "[::1]:$port")
            for path in ("/", "/api/status", "/api/legend", "/static/style.css")
                @test get_as(path, host).status == 403
            end
        end
        # A POST from another origin is 403 and starts nothing; the page's own origin (or none) is served.
        for origin in ("http://evil.example", "null", "http://127.0.0.1:$(port + 1)", "https://127.0.0.1:$port",
            "http://localhost.evil.example:$port")
            @test post_from("/api/start", origin).status == 403
            @test post_from("/api/stop", origin).status == 403
        end
        @test vs_status(s)["run"] === nothing
        r1 = post_from("/api/start", "http://127.0.0.1:$port")
        @test r1.status == 200
        r2 = post_from("/api/start", "http://localhost:$port")
        @test r2.status == 200
        @test vs_body(r2)["run"] == vs_body(r1)["run"] + 1
        @test post_from("/api/stop", "http://localhost:$port").status == 200
        @test vs_post(s, "/api/start").status == 200  # no Origin header: a same-origin form or a script, served
        # A foreign host is refused even with the page's origin.
        resp = HTTP.post(vs_url(s, "/api/start"), ["Host" => "evil.example:$port", "Origin" => "http://127.0.0.1:$port"],
            Dict{String,String}(); status_exception=false, retry=false)
        @test resp.status == 403
    finally
        stop_viewer(s)
    end
end

@testset "a start waiting behind stop_viewer is refused" begin
    s = start_viewer(; port=0, autostep=true)
    run = Int(vs_body(vs_post(s, "/api/start"))["run"])
    task = s.stepper
    @test task isa Task
    # The test holds the control lock, as stop_viewer does while it waits for a period to end; a start arriving then
    # parses its form and waits for the lock. stop_viewer (on this task, so it takes the lock at once) closes the
    # viewer; once the lock is free the waiting start must answer 503 and start nothing.
    lock(s.control)
    pending = @async XxlViewer.start_route(s, HTTP.Request("POST", "/api/start", Pair{String,String}[],
        "seed=$(viewer_defaults(DEFAULT_EXP).seed + 1)"))
    sleep(0.5)
    @test !istaskdone(pending)
    try
        stop_viewer(s)
    finally
        unlock(s.control)
    end
    resp = fetch(pending)
    @test resp.status == 503
    @test occursin("closed", String(resp.body))  # built here, not sent: the body is still the String
    @test istaskdone(task)
    @test s.stepper === nothing
    @test s.run_id == run && s.run.settings.seed == viewer_defaults(DEFAULT_EXP).seed
    t = s.run.model.t
    @test !step_once!(s)
    @test s.run.model.t == t
    @test !isopen(s.server)
end

@testset "static files stay in their folder" begin
    s = start_viewer(; port=0, autostep=false)
    try
        css = vs_get(s, "/static/style.css")
        @test css.status == 200
        @test occursin("text/css", HTTP.header(css, "Content-Type"))
        for path in ("/static/../XxlViewer.jl", "/static/%2e%2e/run.jl", "/static/%2e%2e%2fXxlViewer.jl",
            "/static/..%5cXxlViewer.jl", "/static/missing.css", "/static/")
            @test vs_get(s, path).status == 404
        end
    finally
        stop_viewer(s)
    end
end
