# Stage 6: an opt-in log of rule S's mating attempts (Model.mate_log). Off it costs nothing and draws nothing.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

# A fertile man of the couple's kind, put at (x, y).
function fertile_man(m, x, y; vision=1)
    h = put_agent(m, x, y; sugar=60.0, vision=vision)
    h.sex, h.fertility_start, h.fertility_end, h.initial_sugar, h.age = :M, 12, 50, 60.0, 20
    return h
end

@testset "xxl mate log" begin
    @testset "a birth is logged with its ids and distance" begin
        m = tiny_model(ones(Int, 6, 6); sex=true)
        m.mate_log = MateEvent[]
        f, h = couple(m)
        m.t = 7
        kids = mate!(m, f)
        @test length(kids) == 1
        @test m.mate_log == [MateEvent(7, f.id, h.id, true, 1.0, 1)]
    end

    @testset "a partner out of reach by vision is logged at its distance" begin
        m = tiny_model(ones(Int, 9, 9); sex=true, mate_contact="vision")
        m.mate_log = MateEvent[]
        f = put_agent(m, 2, 2; sugar=60.0, vision=3)
        f.sex, f.fertility_start, f.fertility_end, f.initial_sugar, f.age = :F, 12, 40, 60.0, 20
        h = fertile_man(m, 2, 5)
        @test length(mate!(m, f)) == 1
        @test m.mate_log == [MateEvent(0, f.id, h.id, true, 3.0, 3)]
    end

    @testset "distance is torus distance" begin
        m = tiny_model(ones(Int, 9, 9); sex=true, mate_contact="vision")
        m.mate_log = MateEvent[]
        f = put_agent(m, 0, 0; sugar=60.0, vision=4)
        f.sex, f.fertility_start, f.fertility_end, f.initial_sugar, f.age = :F, 12, 40, 60.0, 20
        h = fertile_man(m, 8, 0)
        mate!(m, f)
        @test [e.distance for e in m.mate_log] == [1.0]
    end

    @testset "no room: logged as not born, and no child" begin
        m = tiny_model(ones(Int, 3, 3); sex=true)
        m.mate_log = MateEvent[]
        f, h = couple(m)
        for x in 0:2, y in 0:2
            agent_at(m, x, y) === nothing && put_agent(m, x, y)
        end
        @test isempty(mate!(m, f))
        @test m.mate_log == [MateEvent(0, f.id, h.id, false, 1.0, 1)]
        @test f.sugar == 60.0
    end

    @testset "a partner that is not fertile, or of the same sex, logs nothing" begin
        m = tiny_model(ones(Int, 6, 6); sex=true)
        m.mate_log = MateEvent[]
        f, h = couple(m)
        h.age = 50
        @test isempty(mate!(m, f))
        h.age, h.sex = 20, :F
        @test isempty(mate!(m, f))
        h.sex, f.sugar = :M, 59.0  # the seeker not fertile
        @test isempty(mate!(m, f))
        @test isempty(m.mate_log)
    end

    @testset "step! empties the log" begin
        m = tiny_model(ones(Int, 6, 6); sex=true)
        m.mate_log = [MateEvent(0, 1, 2, true, 1.0, 1)]
        step!(m)
        @test isempty(m.mate_log)
        m.mate_log = nothing
        step!(m)
        @test m.mate_log === nothing
    end

    # Twelve periods; the standard CSV bytes, and (with the log on) every period's events and the births.
    function twelve(cfg, log)
        m = Model(cfg)
        m.mate_log = log ? MateEvent[] : nothing
        rows = Vector{Vector{Float64}}()
        events = MateEvent[]
        born = Set{Int}()
        for _ in 1:12
            step!(m)
            push!(rows, pushfirst!(collect_metrics(m), m.t))
            log && append!(events, m.mate_log)
            for a in Iterators.flatten((m.agents, m.dead_this_step)), c in a.children
                push!(born, c.id)
            end
        end
        path = tempname()
        Sugarscape.write_seed_csv(path, rows)
        return read(path), events, length(born)
    end

    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1").config
    for (name, cfg) in (("book VI-1", vi1), ("XXL_DEFAULTS VI-1", to_xxl(vi1, XXL_DEFAULTS)))
        @testset "$name: the log changes nothing in the run" begin
            off, _, _ = twelve(cfg, false)
            on, events, births = twelve(cfg, true)
            @test on == off
            @test births > 0
            @test count(e -> e.born, events) == births
            @test all(e -> e.seeker != e.partner && e.distance >= 1.0, events)
        end
    end
end
