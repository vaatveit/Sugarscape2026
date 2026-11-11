# The pollution readings (docs/superpowers/specs/2026-11-11-vi1-pollution-design.md, "The pollution readings"): the
# mean pollution of the land, the mean on the agents' cells and the share of agents on rich land, kept with the combat
# readings and written by the combat study as seed<k>-pollution.csv.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: CombatReadings, combat_period!, pollution_rows, POLLUTION_COLUMNS, rich_cut, run_combat_world,
    combat_seed_done, pollution_path

@testset "pollution readings: rich_cut" begin
    ls = Landscape([0 1; 2 3])
    @test rich_cut(ls) == 2
    @test ((ls.capacity .+ ls.spice_capacity) .>= rich_cut(ls)) == Bool[0 0; 1 1]
    ls = Landscape([0 1; 2 3], [3 0; 0 0])
    @test rich_cut(ls) == 3
end

@testset "pollution readings: the three columns" begin
    @test POLLUTION_COLUMNS == ["t", "mean_pollution", "agent_pollution", "share_rich"]
    cap = reshape(collect(0:15), 4, 4)  # the capacity at (x, y) is x + 4y; the cut is 11
    m = tiny_model(cap; pollution=(1.0, 1.0))
    m.landscape.pollution .= cap
    put_agent(m, 3, 0)  # pollution 3, capacity 3: not rich
    put_agent(m, 3, 3)  # pollution 15, capacity 15: rich
    r = CombatReadings()
    @test pollution_rows(r) == (POLLUTION_COLUMNS, Vector{Float64}[])
    m.t = 4
    combat_period!(r, m)
    _, rows = pollution_rows(r)
    @test rows == [[4.0, 120 / 16, (3.0 + 15.0) / 2, 1 / 2]]
    @test r.rich == (cap .>= 11)
end

@testset "pollution readings: no agents" begin
    m = tiny_model(reshape(collect(0:15), 4, 4); pollution=(1.0, 1.0))
    m.landscape.pollution .= 1.0
    r = CombatReadings()
    combat_period!(r, m)
    row = pollution_rows(r)[2][1]
    @test row[2] == 1.0 && isnan(row[3]) && isnan(row[4])
end

@testset "pollution readings: without pollution there are none" begin
    m = tiny_model(reshape(collect(0:15), 4, 4))
    put_agent(m, 0, 0)
    r = CombatReadings()
    combat_period!(r, m)
    @test isempty(r.pollution_rows) && r.rich === nothing
    @test length(r.rows) == 1
end

@testset "pollution readings: the study's file" begin
    kw = (seeds=1, first_seed=0, periods=4, io=devnull)
    out = mktempdir()
    folder = run_combat_world("today", "VI-1-pollution-t0"; kw..., out=out)
    path = pollution_path(folder, 0)
    @test basename(path) == "seed0-pollution.csv"
    lines = readlines(path)
    @test lines[1] == "t,mean_pollution,agent_pollution,share_rich" && length(lines) == 6
    mean_p = [parse(Float64, split(l, ",")[2]) for l in lines[2:end]]
    @test mean_p[1] == 0 && mean_p[end] > 0
    @test combat_seed_done(folder, 0, 4; pollution=true) && combat_seed_done(folder, 0, 4)
    mtime0 = mtime(joinpath(folder, "seed0.csv"))
    run_combat_world("today", "VI-1-pollution-t0"; kw..., out=out)  # done: skipped
    @test mtime(joinpath(folder, "seed0.csv")) == mtime0
    rm(path)
    @test !combat_seed_done(folder, 0, 4; pollution=true)
    run_combat_world("today", "VI-1-pollution-t0"; kw..., out=out)
    @test isfile(path)

    folder = run_combat_world("today", "VI-1-assim-k4"; seeds=1, first_seed=0, periods=4, io=devnull, out=mktempdir())
    @test !isfile(pollution_path(folder, 0))
end
