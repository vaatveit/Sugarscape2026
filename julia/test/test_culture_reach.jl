# Rule K at combat's reach (docs/superpowers/specs/2026-11-09-vi1-reach-design.md, "VI-1-far" and "VI-1-far-speed"):
# with culture_reach "sight" an agent changes a tag of every agent on combat's look from its position (the 4 lattice
# lines, or the xxl round look without memory); with "attack" of every agent within its speed. An agent with tags 00000
# among agents with 11111: any agent reached changes one tag.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: culture_reach_agents!, culture_neighbors!

const CR_A = [0, 0, 0, 0, 0]
const CR_B = [1, 1, 1, 1, 1]

cr_reached(b) = tags_of(b) != CR_B

# A world of bare sites with culture, 5 tag positions and culture_reach `reach`; with S, xxl round vision and speed S.
function cr_world(n; reach, V, S=nothing, seed=1, kw...)
    xxl = S === nothing ? (;) : (;
        xxl=XxlRules(; vision_shape="disc", speed=(S, S), travel_cost=0.0),
    )
    return tiny_model(
        zeros(Int, n, n);
        tag_length=5,
        culture=true,
        culture_reach=reach,
        vision=(V, V),
        seed=seed,
        xxl...,
        kw...,
    )
end

function cr_agent(m, x, y, tags; V, S=nothing)
    a = put_agent(m, x, y; vision=V)
    S === nothing || (a.speed = S)
    return tag!(a, tags)
end

@testset "test_sight_reaches_along_line" begin
    for s in 1:20
        m = cr_world(20; reach="sight", V=4, seed=s)
        a = cr_agent(m, 10, 10, CR_A; V=4)
        line = cr_agent(m, 13, 10, CR_B; V=4)  # 3 sites along a line
        diag = cr_agent(m, 11, 11, CR_B; V=4)  # off the lines
        far = cr_agent(m, 16, 10, CR_B; V=4)  # 6 sites along, past vision
        culture_transmit!(m, a)
        @test cr_reached(line)
        @test !cr_reached(diag)
        @test !cr_reached(far)
        @test tags_of(a) == CR_A
    end
end

@testset "test_sight_xxl_look" begin
    near4 = far8 = 0
    for s in 1:50
        m = cr_world(30; reach="sight", V=5, S=1, seed=s)
        a = cr_agent(m, 10, 10, CR_A; V=5, S=1)
        b4 = cr_agent(m, 14, 10, CR_B; V=5, S=1)  # in the sampled ring
        b8 = cr_agent(m, 10, 18, CR_B; V=5, S=1)  # past vision
        culture_transmit!(m, a)
        near4 += cr_reached(b4)
        far8 += cr_reached(b8)
    end
    @test near4 > 0
    @test far8 == 0
end

@testset "test_attack_reach" begin
    for s in 1:20
        m = cr_world(30; reach="attack", V=3, S=3, seed=s)
        a = cr_agent(m, 10, 10, CR_A; V=3, S=3)
        b3 = cr_agent(m, 13, 10, CR_B; V=3, S=3)
        b4 = cr_agent(m, 10, 14, CR_B; V=3, S=3)
        culture_transmit!(m, a)
        @test cr_reached(b3)
        @test !cr_reached(b4)
    end
end

@testset "test_reach_excludes_self_and_duplicates" begin  # Review Focus 3
    # 11x11 tori filled with agents, at the largest vision the config allows (less than half the grid): the round look
    # holds the agent's own site, and the reach is as wide as it can be.
    cases = (
        (11, "sight", 5, nothing),  # the 4 lattice lines out to 5
        (11, "sight", 5, 1),  # round look: the 4 adjacent sites and the sampled ring out to 5
        (11, "attack", 5, 5),  # the speed disc of radius 5
    )
    for (n, reach, V, S) in cases, s in 1:10
        m = cr_world(n; reach=reach, V=V, S=S, seed=s)
        all_agents = [cr_agent(m, x, y, CR_B; V=V, S=S) for x in 0:(n - 1), y in 0:(n - 1)]
        for a in all_agents
            out = culture_reach_agents!(Agent[], m, a)
            @test !any(o -> o === a, out)
            @test length(Set(objectid.(out))) == length(out)
            @test !isempty(out)
        end
    end
end

@testset "test_culture_look_leaves_move_buffers" begin  # Review Focus 4
    for s in 1:10
        m = cr_world(
            30; reach="sight", V=6, S=2, seed=s, combat_alpha=Inf, combat_hostility=1.0
        )
        a = cr_agent(m, 10, 10, CR_A; V=6, S=2)
        for (x, y) in ((12, 10), (10, 13), (14, 14), (7, 10), (10, 5))
            b = cr_agent(m, x, y, CR_B; V=6, S=2)
            b.sugar = 100.0
        end
        combat_move!(m, a)
        looked, threat = copy(m.looked), copy(m.threat_looked)
        culture_transmit!(m, a)
        @test m.looked == looked
        @test m.threat_looked == threat
    end
    # the lattice look: the move's line buffer is left alone too
    m = cr_world(20; reach="sight", V=4, seed=1, combat_alpha=Inf, combat_hostility=1.0)
    a = cr_agent(m, 10, 10, CR_A; V=4)
    cr_agent(m, 13, 10, CR_B; V=4)
    combat_move!(m, a)
    append!(empty!(m.line), (-1, -2))  # a marker: rule K's look would write distances 1-4 over it
    culture_transmit!(m, a)
    @test m.line == [-1, -2]
end

@testset "test_readings_neighbourhood_unchanged" begin
    base = (; culture=true, tag_length=5, seed=3)
    m0 = Model(replace_config(Config(); base...))
    m1 = Model(replace_config(Config(); base..., culture_reach="sight"))
    @test length(m0.agents) == length(m1.agents) > 0
    for (a0, a1) in zip(m0.agents, m1.agents)
        @test (a0.x, a0.y) == (a1.x, a1.y)
        ids0 = [o.id for o in culture_neighbors!(Agent[], m0, a0)]
        ids1 = [o.id for o in culture_neighbors!(Agent[], m1, a1)]
        @test ids0 == ids1
    end
end

@testset "test_checkpoint_leaves_culture_scratch_out" begin
    m = cr_world(30; reach="sight", V=5, S=1, seed=1)
    a = cr_agent(m, 10, 10, CR_A; V=5, S=1)
    b = cr_agent(m, 11, 10, CR_B; V=5, S=1)
    culture_transmit!(m, a)
    @test !isempty(m.culture_reached)
    r = Sugarscape.model_from_flat(Sugarscape.flat_model(m))
    @test isempty(r.culture_reached)
    @test [o.id for o in culture_reach_agents!(Agent[], r, r.grid[11, 11])] == [b.id]
end
