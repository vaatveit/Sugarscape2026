# xxl (revised): the free step (docs/superpowers/specs/2026-10-29-xxl-revised-design.md, "The changes", item 3). A move
# whose target is within `free_step` costs nothing, a move toward a farther target pays `travel_cost` per site moved, and
# the valuation (rule 2's net value and its starve-on-the-way cutoff) agrees with what is paid.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: trip_cost, NO_WELFARE

# A model on `cap` with speed S, travel cost c and free step `free`, with one agent at (x, y). Round vision by default:
# within the near radius (the speed) it looks at every site, diagonals too.
function free_world(
    cap, x, y; S=1, c=0.1, free=1.5, vision=S, sugar=10.0, metabolism=1, shape="disc"
)
    rules = XxlRules(; vision_shape=shape, speed=(S, S), travel_cost=c, free_step=free)
    m = tiny_model(cap; xxl=rules, vision=(vision, vision))
    a = put_agent(m, x, y; vision=vision, sugar=sugar, metabolism=metabolism)
    a.speed = S
    return m, a
end

# What `metabolize!` charges `a` beyond its metabolism this period.
function travel_charge!(m, a)
    before = a.sugar
    metabolize!(m, a)
    return before - a.sugar - sugar_burn(a)
end

@testset "xxl free step" begin
    @testset "boundary" begin
        @test trip_cost(0.1, 1.5, sqrt(2)) == 0.0
        @test trip_cost(0.1, 1.5, 1.5) == 0.0
        @test trip_cost(0.1, 1.5, 2.0) == 0.2
        @test trip_cost(0.1, 0.0, 0.0) == 0.0
        @test trip_cost(0.1, 0.0, 1.0) == 0.1

        # One commodity, speed 2: both distances are one period (T = 1), so only the trip's cost differs.
        m, a = free_world(zeros(Int, 11, 11), 5, 5; S=2, sugar=10.0)
        m0, a0 = free_world(zeros(Int, 11, 11), 5, 5; S=2, c=0.0, sugar=10.0)
        @test net_value(m, a, 6, 6, sqrt(2), 4.0, 0.0) ==
            net_value(m0, a0, 6, 6, sqrt(2), 4.0, 0.0)
        @test net_value(m, a, 7, 5, 2.0, 4.0, 0.0) ≈
            net_value(m0, a0, 7, 5, 2.0, 4.0, 0.0) - 0.2
        @test net_value(a, NO_WELFARE, false, 0.1, 1.5, sqrt(2), 4.0, 0.0) == 10.0 + 4.0
        @test net_value(a, NO_WELFARE, false, 0.1, 1.5, 2.0, 4.0, 0.0) == 10.0 - 0.2 + 4.0

        # The starve-on-the-way cutoff: 0.15 sugar, speed 1, metabolism 0 (T = 2 for both, no burn on the way).
        m, a = free_world(zeros(Int, 11, 11), 5, 5; S=1, sugar=0.15, metabolism=0)
        @test net_value(m, a, 7, 5, 2.0, 4.0, 0.0) == -Inf   # 0.15 - 0.2 <= 0
        @test isfinite(net_value(m, a, 6, 6, sqrt(2), 4.0, 0.0))   # free: 0.15 > 0

        # In a move: a diagonal step to a full site is free, a 2-site step pays 0.2.
        cap = zeros(Int, 11, 11)
        cap[7, 7] = 4   # (6, 6)
        m, a = free_world(cap, 5, 5; S=2, sugar=10.0)
        speed_move!(m, a)
        @test (a.x, a.y) == (6, 6) && a.moved_dist == sqrt(2) && a.travel_free
        metabolize!(m, a)
        @test a.sugar == 10.0 + 4.0 - 1
        m, a = free_world(cap, 4, 6; S=2, sugar=10.0)
        speed_move!(m, a)
        @test (a.x, a.y) == (6, 6) && a.moved_dist == 2.0 && !a.travel_free
        metabolize!(m, a)
        @test a.sugar == 10.0 + 4.0 - (1 + 0.1 * 2.0)
    end

    @testset "the travel-cost trap" begin
        # Metabolism 2 on capacity-2 land: each period the agent steps to a full Moore neighbour to eat.
        function holdings(free; periods=10)
            m, a = free_world(fill(2, 9, 9), 4, 4; S=1, free=free, sugar=10.0, metabolism=2)
            m.landscape.sugar[5, 5] = 0.0   # its own site is harvested: it must step to eat
            out = Float64[]
            for _ in 1:periods
                step!(m)
                @test a.moved && a.moved_dist <= sqrt(2)
                push!(out, a.sugar)
            end
            return out
        end
        @test all(==(10.0), holdings(1.5))
        @test holdings(0.0) ≈ [10.0 - 0.1 * k for k in 1:10]
    end

    @testset "a long trip pays until the target is within the free step" begin
        cap = zeros(Int, 15, 15)
        cap[9, 6] = 4   # (8, 5): 3 east
        # Lattice vision looks at every site along the axis (the disc's ring is drawn at random).
        m, a = free_world(cap, 5, 5; S=1, vision=3, sugar=10.0, shape="lattice")
        charges = Float64[]
        for _ in 1:3
            move!(m, a)
            push!(charges, travel_charge!(m, a))
        end
        @test (a.x, a.y) == (8, 5)
        @test charges[1] ≈ 0.1 && charges[2] ≈ 0.1
        @test charges[3] == 0.0
    end

    @testset "free_step = 0 charges every move" begin
        cap = zeros(Int, 11, 11)
        cap[7, 7] = 4   # (6, 6)
        m, a = free_world(cap, 5, 5; S=2, free=0.0, sugar=10.0)
        speed_move!(m, a)
        @test (a.x, a.y) == (6, 6) && !a.travel_free
        metabolize!(m, a)
        @test a.sugar == 10.0 + 4.0 - (1 + 0.1 * sqrt(2))
        stay = zeros(Int, 11, 11)
        stay[6, 6] = 4   # the own site (5, 5) is best
        m, a = free_world(stay, 5, 5; S=2, free=0.0, sugar=10.0)
        speed_move!(m, a)
        @test (a.x, a.y) == (5, 5) && a.travel_free && a.moved_dist == 0.0
    end
end
