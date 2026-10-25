# Lockstep replay: Python's recorded random choices (agent orders, direction orders) fed to the Julia model must give
# Python's trajectory exactly (julia/bridge/lockstep.py writes fixtures/lockstep.toml).
using Sugarscape, Test, TOML
using Random: AbstractRNG
using Random: Random

"""An RNG that replays Python's recorded permutations, in Python's call order; any other draw is an error."""
struct ScriptedRNG <: AbstractRNG
    events::Vector{Any}  # [kind, values]: "order" (agent ids), "dirs" or "perm" (1-based indices)
    byid::Dict{Int,Agent}
    used::Vector{Int}
end

function next_event(r::ScriptedRNG, kinds)
    r.used[1] += 1
    kind, values = r.events[r.used[1]]
    kind in kinds ||
        error("draw $(r.used[1]): Python drew $kind here, Julia wants one of $kinds")
    return kind, values
end

Sugarscape.random_directions(r::ScriptedRNG) = NTuple{4,Int}(next_event(r, ("dirs",))[2])

function Random.shuffle!(r::ScriptedRNG, v::Vector{Agent})
    kind, values = next_event(r, ("order", "perm"))
    length(values) == length(v) ||
        error("Python permuted $(length(values)) agents here, Julia $(length(v))")
    if kind == "order"
        v .= [r.byid[id] for id in values]
    else  # the neighbours, visited in the order Python's permutation gives
        v .= v[values]
    end
    return v
end

function lockbits(v)
    return foldl(
        (acc, (i, b)) -> acc | (UInt64(b) << (i - 1)), enumerate(v); init=UInt64(0)
    )
end
near(a, b) = isapprox(a, b; rtol=1e-12, atol=1e-9)

for case in TOML.parsefile(joinpath(@__DIR__, "fixtures", "lockstep.toml"))["case"]
    @testset "lockstep $(case["name"])" begin
        d = Dict{String,Any}(case["config"])
        d["initial_population"], d["initial_blocks"] = 0, Any[]
        rng = ScriptedRNG(case["events"], Dict{Int,Agent}(), [0])
        m = Model(config_from_toml(d); rng=rng)
        for s in case["start"]
            a = new_agent!(
                m,
                s["x"],
                s["y"],
                s["vision"],
                s["metabolism"],
                s["sugar"];
                max_age=get(s, "max_age", Inf),
            )
            @assert a.id == s["id"]
            a.age = s["age"]
            if haskey(s, "spice")
                a.spice, a.initial_spice = s["spice"], s["spice"]
                a.spice_metabolism, a.foresight = s["spice_metabolism"], s["foresight"]
            end
            haskey(s, "tags") &&
                ((a.tags, a.ntags) = (lockbits(s["tags"]), length(s["tags"])))
            rng.byid[a.id] = a
        end
        first_bad = 0
        for (t, want) in enumerate(case["states"])
            step!(m)
            ok =
                length(m.agents) == want["population"] &&
                near(sum(m.landscape.sugar), want["sugar_total"]) &&
                near(sum(m.landscape.spice), want["spice_total"]) &&
                length(m.trade_log) == want["trades"] &&
                near(sum(m.landscape.pollution), want["pollution_total"])
            ok || (first_bad=t; break)
        end
        @test first_bad == 0
        @test rng.used == [length(case["events"])]  # every recorded choice, no more
        got = sort(m.agents; by=a -> a.id)
        @test [(a.id, a.x, a.y, a.age) for a in got] == [(e["id"], e["x"], e["y"], e["age"]) for e in case["end"]]
        @test all(
            near(a.sugar, e["sugar"]) && near(a.spice, get(e, "spice", 0.0)) for
            (a, e) in zip(got, case["end"])
        )
        w, h = size(m.landscape.sugar)
        @test all(
            near.(m.landscape.sugar, [case["end_sugar"][x][y] for x in 1:w, y in 1:h])
        )
        @test all(
            near.(m.landscape.spice, [case["end_spice"][x][y] for x in 1:w, y in 1:h])
        )
        @test all(
            near.(
                m.landscape.pollution, [case["end_pollution"][x][y] for x in 1:w, y in 1:h]
            ),
        )
    end
end
