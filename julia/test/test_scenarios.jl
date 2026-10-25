# Replays the cross-language scenarios: small states whose outcome cannot depend on the agents' order or on random
# draws, with the end state the Python model reached (julia/bridge/scenarios.py writes fixtures/scenarios.toml).
using Sugarscape, Test, TOML
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

const FIXTURES = joinpath(@__DIR__, "fixtures", "scenarios.toml")
const SEXES = Dict("F" => :F, "M" => :M)

function bitstring_of(v)
    return foldl(
        (acc, (i, b)) -> acc | (UInt64(b) << (i - 1)), enumerate(v); init=UInt64(0)
    )
end

function build(sc)
    cfg = config_from_toml(
        merge(
            Dict{String,Any}(
                "width" => sc["width"], "height" => sc["height"], "initial_population" => 0
            ),
            sc["config"],
        ),
    )
    cap = [sc["capacity"][x][y] for x in 1:sc["width"], y in 1:sc["height"]]
    m = Model(cfg; capacity=cap)
    agents = Agent[]
    for spec in sc["agents"]
        max_age = get(spec, "max_age", Inf)
        a = new_agent!(
            m,
            spec["x"],
            spec["y"],
            spec["vision"],
            spec["metabolism"],
            spec["sugar"];
            max_age=max_age,
        )
        for (k, v) in spec
            k in ("x", "y", "vision", "metabolism", "sugar", "max_age", "children") &&
                continue
            if k == "sex"
                a.sex = SEXES[v]
            elseif k == "tags"
                a.tags, a.ntags = bitstring_of(v), length(v)
            else
                setfield!(a, Symbol(k), convert(fieldtype(Agent, Symbol(k)), v))
            end
        end
        push!(agents, a)
    end
    for (spec, a) in zip(sc["agents"], agents)
        for i in get(spec, "children", Int[])
            push!(a.children, agents[i + 1])
        end
    end
    return m, agents
end

grid(rows, w, h) = [rows[x][y] for x in 1:w, y in 1:h]

for sc in TOML.parsefile(FIXTURES)["scenario"]
    @testset "$(sc["name"])" begin
        m, agents = build(sc)
        for (rule, who...) in get(sc, "actions", [])
            rule == "bargain" || error("unknown scenario action $rule")
            bargain!(m, agents[who[1] + 1], agents[who[2] + 1])
        end
        for _ in 1:sc["steps"]
            step!(m)
        end
        want = sc["expected"]
        got = sort(m.agents; by=a -> a.id)
        @test length(got) == length(want["agents"])
        for (a, e) in zip(got, want["agents"])
            @test (a.x, a.y, a.age) == (e["x"], e["y"], e["age"])
            @test near(a.sugar, e["sugar"]) && near(a.spice, e["spice"])
        end
        w, h = sc["width"], sc["height"]
        @test all(near.(m.landscape.sugar, grid(want["sugar"], w, h)))
        @test all(near.(m.landscape.spice, grid(want["spice"], w, h)))
        @test all(near.(m.landscape.pollution, grid(want["pollution"], w, h)))
    end
end
