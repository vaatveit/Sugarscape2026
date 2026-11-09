# xxl rule 7 with spice (docs/superpowers/specs/2026-11-08-vi1-combat-design.md, "The rule"): wealth is sugar plus
# spice, the loot both goods, a site valued by net_value with the agent's welfare and the loot, and the landing
# harvested through harvest!. Calls `xxl_combat_move!` directly, as test_xxl_combat.jl does.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: xxl_combat_move!

# test_xxl_combat.jl's combat_world, with spice on: a 30x30 world of bare sites, vision `V`, speed `S`, round vision
# (or `shape`), memory `M`, combat with alpha = Inf, 11 tag positions.
function spice_world(; S=3, V=S, shape="disc", M=0, kw...)
    return tiny_model(
        zeros(Int, 30, 30);
        tag_length=11,
        combat_alpha=Inf,
        spice=true,
        xxl=XxlRules(; vision_shape=shape, speed=(S, S), travel_cost=0.0, memory=M),
        vision=(V, V),
        kw...,
    )
end

# test_xxl_combat.jl's fighter on the sugar-and-spice landscape: tribe `side` (:blue tags all 0, :red all 1) at (x, y),
# holding `sugar` and `spice`, metabolisms 1 and 1, no foresight.
function spice_fighter(m, x, y, side, sugar, spice; V, S)
    a = put_agent(m, x, y; vision=V, sugar=sugar)
    a.speed = S
    tag!(a, fill(side === :red ? 1 : 0, 11))
    a.spice, a.metabolism, a.spice_metabolism, a.foresight = spice, 1, 1, 0
    return a
end

@testset "xxl combat takes all sugar and spice" begin
    m = spice_world(; S=3)
    blue = spice_fighter(m, 10, 10, :blue, 20.0, 20.0; V=3, S=3)
    red = spice_fighter(m, 12, 11, :red, 8.0, 5.0; V=3, S=3)
    m.landscape.sugar[12 + 1, 11 + 1] = 2.0
    m.landscape.spice[12 + 1, 11 + 1] = 3.0
    xxl_combat_move!(m, blue)
    @test !red.alive
    @test (blue.x, blue.y) == (12, 11)
    @test (blue.sugar, blue.spice) == (28.0 + 2.0, 25.0 + 3.0)
    @test red.id in m.killed
end

@testset "xxl combat: wealthier by both goods is not attacked" begin
    m = spice_world(; S=3)
    blue = spice_fighter(m, 10, 10, :blue, 20.0, 1.0; V=3, S=3)
    red = spice_fighter(m, 12, 11, :red, 5.0, 20.0; V=3, S=3)   # 25 > 21, though its sugar is less
    xxl_combat_move!(m, blue)
    @test red.alive
    @test (blue.sugar, blue.spice) == (20.0, 1.0)
end

@testset "xxl combat: retaliation counts spice" begin
    m = spice_world(; S=3)
    blue = spice_fighter(m, 10, 10, :blue, 20.0, 20.0; V=3, S=3)
    red = spice_fighter(m, 12, 11, :red, 8.0, 5.0; V=3, S=3)
    # 2.2 from the target and 4.5 from blue: wealth 70 > 40 + 13, though its sugar 10 < 20 + 8.
    spice_fighter(m, 14, 12, :red, 10.0, 60.0; V=3, S=3)
    xxl_combat_move!(m, blue)
    @test red.alive
    @test (blue.x, blue.y) != (12, 11)
end

@testset "xxl combat: the value includes the loot" begin
    m = spice_world(; S=3)
    blue = spice_fighter(m, 10, 10, :blue, 20.0, 2.0; V=3, S=3)   # short of spice
    red = spice_fighter(m, 12, 10, :red, 0.0, 6.0; V=3, S=3)      # on a bare site, 2 away
    m.landscape.sugar[8 + 1, 10 + 1] = 3.0                        # an empty site, 2 away the other way
    xxl_combat_move!(m, blue)
    @test !red.alive
    @test (blue.x, blue.y) == (12, 10)
    @test (blue.sugar, blue.spice) == (20.0, 8.0)
end

@testset "xxl combat: a trip that starves on spice is skipped" begin
    # The lattice look with stride 1 sees the target 8 away on the axis. Speed 2: T = 4, so 3 periods on the way.
    function far_world(spice)
        m = spice_world(; S=2, V=10, shape="lattice", look_stride=1)
        blue = spice_fighter(m, 10, 10, :blue, 20.0, spice; V=10, S=2)
        m.landscape.sugar[18 + 1, 10 + 1] = 10.0
        m.landscape.spice[18 + 1, 10 + 1] = 10.0
        return m, blue
    end
    m, blue = far_world(2.5)   # 2.5 - 3 x 1 <= 0: net_value is -Inf
    xxl_combat_move!(m, blue)
    @test (blue.x, blue.y) == (10, 10)
    @test !blue.moved
    m, blue = far_world(10.0)   # with spice for the trip it walks toward the target
    xxl_combat_move!(m, blue)
    @test (blue.x, blue.y) == (12, 10)
end

@testset "xxl combat: remembered sites are valued with their spice" begin
    m = spice_world(; S=3, M=8)
    blue = spice_fighter(m, 10, 10, :blue, 20.0, 4.0; V=3, S=3)   # short of spice
    push!(blue.memory, Remembered(18, 10, 0.0, 10.0, 0.0, 0))     # beyond vision, spice only
    m.landscape.sugar[12 + 1, 10 + 1] = 2.0    # in sight, a little sugar
    m.landscape.spice[13 + 1, 10 + 1] = 2.0    # the walk's landing site, 3 along
    m.landscape.spice[10 + 1, 12 + 1] = 3.0    # in sight, 3.6 from the landing site
    xxl_combat_move!(m, blue)
    @test blue.target_remembered
    @test (blue.x, blue.y) == (13, 10)
    @test blue.spice == 6.0
    @test m.landscape.spice[13 + 1, 10 + 1] == 0.0   # harvested
    # The memory is ranked from (13, 10) with the spice, each 3.6 to 5 away costing a period's wait: the remembered site
    # first (W(19, 15)), then the looked-at site with spice 3 (W(19, 8)), ahead of the sugar site (W(22, 6)) and the
    # bare sites (W(20, 6)).
    @test blue.memory[1] == Remembered(18, 10, 0.0, 10.0, 0.0, 0)
    @test blue.memory[2] == Remembered(10, 12, 0.0, 3.0, 0.0, 0)
end

@testset "xxl combat: income excludes the loot" begin
    m = spice_world(; S=3)
    blue = spice_fighter(m, 10, 10, :blue, 20.0, 20.0; V=3, S=3)
    red = spice_fighter(m, 12, 11, :red, 8.0, 5.0; V=3, S=3)
    m.landscape.sugar[12 + 1, 11 + 1] = 4.0
    xxl_combat_move!(m, blue)
    @test !red.alive
    @test blue.last_income == 4.0
end
