# Lockstep replay: Python's recorded random choices (agent orders, direction orders) fed to the Julia model must give
# Python's trajectory exactly (julia/bridge/lockstep.py writes fixtures/lockstep.toml).
using Sugarscape, Test, TOML
using Random: AbstractRNG
using Random: Random

"""An RNG that replays Python's recorded choices, and refuses any other draw."""
struct ScriptedRNG <: AbstractRNG
    orders::Vector{Vector{Int}}
    dirs::Vector{Vector{Int}}
    byid::Dict{Int,Agent}
    next::Vector{Int}  # [orders used, directions used]
end

function Sugarscape.random_directions(r::ScriptedRNG)
    r.next[2] += 1
    return NTuple{4,Int}(r.dirs[r.next[2]])
end

function Random.shuffle!(r::ScriptedRNG, order::Vector{Agent})
    r.next[1] += 1
    ids = r.orders[r.next[1]]
    length(ids) == length(order) ||
        error("Python's order has $(length(ids)) agents, Julia's $(length(order))")
    for (i, id) in enumerate(ids)
        order[i] = r.byid[id]
    end
    return order
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
        rng = ScriptedRNG(case["orders"], case["dirs"], Dict{Int,Agent}(), [0, 0])
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
                near(sum(m.landscape.pollution), want["pollution_total"])
            ok || (first_bad=t; break)
        end
        @test first_bad == 0
        @test rng.next == [length(case["orders"]), length(case["dirs"])]  # every recorded choice, no more
        got = sort(m.agents; by=a -> a.id)
        @test [(a.id, a.x, a.y, a.age) for a in got] == [(e["id"], e["x"], e["y"], e["age"]) for e in case["end"]]
        @test all(near(a.sugar, e["sugar"]) for (a, e) in zip(got, case["end"]))
        w, h = size(m.landscape.sugar)
        @test all(
            near.(m.landscape.sugar, [case["end_sugar"][x][y] for x in 1:w, y in 1:h])
        )
        @test all(
            near.(
                m.landscape.pollution, [case["end_pollution"][x][y] for x in 1:w, y in 1:h]
            ),
        )
    end
end
