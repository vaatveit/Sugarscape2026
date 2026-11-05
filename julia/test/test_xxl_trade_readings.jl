# xxl (stage 5): the trade readings (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 1"). Hand-built worlds
# pin the health classes, the exchange counts, the 10-period windows and the neighbour columns; a short VI-1 run shows
# the rows add up, the snapshot holds who it should, and the observer leaves the run alone.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: TradeReadings, trade_period!, trade_rows, agent_rows, with_steps

const TR_REG = load_registry()
const TR_HEADER = [
    "t", "healthy", "recovering", "sick", "exchanges", "exchanges_hh", "exchanges_hs", "exchanges_ss",
    "exchanges_recovering", "sick_traders", "healthy_healthy_10", "walked",
    "pairs_hh", "pairs_hs", "pairs_ss", "gap_healthy", "gap_sick", "healthy_healthy_10_strict",
    "exchanges_HH", "exchanges_HX", "gap_strict", "pairs_HH", "pairs_HX", "meetings", "meeting_price_sd",
]
# The columns read only every tenth period, NaN otherwise.
const TR_TENTH = ("pairs_hh", "pairs_hs", "pairs_ss", "gap_healthy", "gap_sick", "gap_strict", "pairs_HH", "pairs_HX")
const TR_AGENT_HEADER = [
    "id", "metabolism", "spice_metabolism", "vision", "age_start", "sugar_start", "spice_start", "sugar_end",
    "spice_end", "exchanges", "exchanges_healthy_partner", "recovering_start", "recovering_in_window",
]

# A 5 x 5 market with no sugar; `trader` puts an agent that trades with a partner of the opposite holdings.
tr_market() = tiny_model(zeros(Int, 5, 5); spice=true, trade=true)

function tr_trader(m, x, y; sugar, spice, sick=false)
    a = put_agent(m, x, y; sugar=sugar)
    a.spice, a.spice_metabolism = spice, 1
    sick && push!(a.diseases, 1)
    return a
end

# Period `t` of a hand-built world: the period label, the exchanges the test makes, the observer's end of period.
function tr_period!(r, m, t, deals=() -> nothing)
    m.t = t
    empty!(m.trade_log)
    deals()
    trade_period!(r, m)
    return r.rows[end]
end

val(row, name) = row[findfirst(==(name), TR_HEADER)]
agent_val(row, name) = row[findfirst(==(name), TR_AGENT_HEADER)]

# VI-1 under the xxl defaults with Rule 13 on (local price, guard 5), shrunk to 50 x 50 and 200 agents: the xl landscape
# gives way to the book map, and the vision (6, 10) keeps the speed (1, 6) valid. Disc vision, speed, memory, a radius of
# 1.5 and the generated founders' disease list are all in play, so agents walk and the neighbours are not von Neumann.
function tr_config(; trade_price=nothing)
    vi1 = find_experiment(TR_REG, "VI-1")
    rules = replace_rules(XXL_DEFAULTS; landscape="xl", trade_move="local", trade_guard=5, trade_price=trade_price)
    return replace_config(
        to_xxl(vi1.config, rules);
        width=50, height=50, initial_population=200, vision=(6, 10), look_stride=1, sugar_map="sugar-map.txt",
    )
end

# A short VI-1 world as `tr_config` gives it, stepped with the observer after each period; and the agents sick at
# period 0.
function tr_run(periods; window=(21, 30))
    cfg = tr_config()
    m = Model(replace_config(cfg; seed=cfg.seed))
    r = TradeReadings(; window=window)
    start_sick = Set(a.id for a in m.agents if !isempty(a.diseases))
    trade_period!(r, m)  # period 0, as timed_seed does
    log = NamedTuple[]
    for _ in 1:periods
        step!(m)
        trade_period!(r, m)
        sick = Set(a.id for a in m.agents if !isempty(a.diseases))
        traders = Set(x.id for e in m.trade_log for x in (e.a, e.b) if !isempty(x.diseases))
        push!(log, (t=m.t, exchanges=length(m.trade_log), n=length(m.agents), alive=Set(a.id for a in m.agents),
            walked=isempty(m.agents) ? NaN : sum(a.moved_dist for a in m.agents) / length(m.agents),
            sick=sick, sick_traders=length(traders), partners=[(e.a.id, e.b.id) for e in m.trade_log],
            partners_sick=[(!isempty(e.a.diseases), !isempty(e.b.diseases)) for e in m.trade_log]))
    end
    return m, r, log, start_sick
end

@testset "xxl trade readings" begin
    @testset "the columns" begin
        header, rows = trade_rows(TradeReadings(; window=(1, 5)))
        @test header == TR_HEADER && isempty(rows)
        header, rows = agent_rows(TradeReadings(; window=(1, 5)))
        @test header == TR_AGENT_HEADER && isempty(rows)
        @test_throws ArgumentError TradeReadings(; window=(0, 5))
        @test_throws ArgumentError TradeReadings(; window=(6, 5))
    end

    @testset "exchanges by the two agents' health" begin
        m = tr_market()
        hh = (tr_trader(m, 0, 0; sugar=5.0, spice=8.0), tr_trader(m, 0, 1; sugar=15.0, spice=2.0))  # both healthy
        hs = (tr_trader(m, 2, 0; sugar=5.0, spice=8.0), tr_trader(m, 2, 1; sugar=15.0, spice=2.0, sick=true))
        ss = (tr_trader(m, 4, 0; sugar=5.0, spice=8.0, sick=true), tr_trader(m, 4, 1; sugar=15.0, spice=2.0, sick=true))
        rh = (tr_trader(m, 0, 3; sugar=5.0, spice=8.0, sick=true), tr_trader(m, 0, 4; sugar=15.0, spice=2.0))  # recovers
        r = TradeReadings(; window=(1, 5))
        row = tr_period!(r, m, 1)  # rh[1] is sick now; nothing is traded
        @test val(row, "healthy") == 4 && val(row, "sick") == 4 && val(row, "recovering") == 0
        @test val(row, "exchanges") == 0 && val(row, "sick_traders") == 0 && isnan(val(row, "gap_sick"))
        empty!(rh[1].diseases)  # recovered: recovering from here on
        row = tr_period!(r, m, 2, () -> foreach(p -> bargain!(m, p...), (hh, hs, ss, rh)))
        n(pair) = count(e -> (e.a === pair[1] || e.a === pair[2]), m.trade_log)
        @test all(>(0), n.((hh, hs, ss, rh)))
        @test val(row, "exchanges") == length(m.trade_log)
        @test val(row, "exchanges_hh") == n(hh) + n(rh)  # a recovering agent counts as healthy here
        @test val(row, "exchanges_hs") == n(hs)
        @test val(row, "exchanges_ss") == n(ss)
        @test val(row, "exchanges_recovering") == n(rh)
        # the strict counts: both strictly healthy (hh alone), exactly one (hs, and rh with its recovering agent)
        @test val(row, "exchanges_HH") == n(hh)
        @test val(row, "exchanges_HX") == n(hs) + n(rh)
        @test val(row, "sick_traders") == 3  # one sick agent in hs, two in ss; the recovered one is not sick
        @test (val(row, "healthy"), val(row, "recovering"), val(row, "sick")) == (4, 1, 3)
    end

    @testset "healthy_healthy_10 counts the period of the exchange and the nine after" begin
        m = tr_market()
        a = tr_trader(m, 1, 1; sugar=5.0, spice=8.0)
        b = tr_trader(m, 1, 2; sugar=15.0, spice=2.0)
        c = tr_trader(m, 3, 3; sugar=10.0, spice=10.0)
        d = tr_trader(m, 4, 1; sugar=10.0, spice=10.0, sick=true)  # sick in periods 1-2, then recovering for 10
        e = tr_trader(m, 3, 4; sugar=10.0, spice=10.0, sick=true)  # sick throughout, next to c
        r = TradeReadings(; window=(1, 14))
        rows = Dict{Int,Vector{Float64}}()
        for t in 1:14
            t == 3 && empty!(d.diseases)
            rows[t] = tr_period!(r, m, t, () -> t == 3 && bargain!(m, a, b))
        end
        @test val(rows[3], "exchanges") == 2 && val(rows[3], "exchanges_hh") == 2
        health(t) = Tuple(val(rows[t], k) for k in ("healthy", "recovering", "sick"))
        @test health(1) == (3, 0, 2) && health(2) == (3, 0, 2)
        @test health(3) == (3, 1, 1) && health(12) == (3, 1, 1)  # sick last in period 2: recovering in 3-12
        @test health(13) == (4, 0, 1) && health(14) == (4, 0, 1)
        hh10(t) = val(rows[t], "healthy_healthy_10")
        strict(t) = val(rows[t], "healthy_healthy_10_strict")
        @test hh10(1) == 0 && hh10(2) == 0 && strict(1) == 0 && strict(2) == 0
        @test all(t -> hh10(t) ≈ 2 / 4, 3:12)  # a and b of the four with no disease (d recovering), through period 12
        @test all(t -> strict(t) ≈ 2 / 3, 3:12)  # a and b of the three strictly healthy
        @test hh10(13) == 0 && hh10(14) == 0  # not in 13: a, b are out of the window
        @test strict(13) == 0 && strict(14) == 0
    end

    @testset "a recovering agent's exchange counts in healthy_healthy_10, not in the strict share" begin
        m = tr_market()
        h = tr_trader(m, 1, 1; sugar=5.0, spice=8.0)
        q = tr_trader(m, 1, 2; sugar=15.0, spice=2.0, sick=true)  # sick in period 1, recovering from 2
        c = tr_trader(m, 3, 3; sugar=10.0, spice=10.0)
        r = TradeReadings(; window=(1, 5))
        tr_period!(r, m, 1)
        empty!(q.diseases)
        row = tr_period!(r, m, 2, () -> bargain!(m, h, q))
        @test val(row, "exchanges") > 0 && val(row, "exchanges_hh") == val(row, "exchanges")
        @test (val(row, "healthy"), val(row, "recovering"), val(row, "sick")) == (2, 1, 0)
        @test val(row, "healthy_healthy_10") ≈ 2 / 3  # h and q, of h, q and c
        @test val(row, "healthy_healthy_10_strict") == 0  # h's partner was recovering, and q isn't strictly healthy
        # with no one healthy or no one without disease, the shares are undefined
        m = tr_market()
        q = tr_trader(m, 1, 2; sugar=15.0, spice=2.0, sick=true)
        r = TradeReadings(; window=(1, 5))
        @test isnan(val(tr_period!(r, m, 1), "healthy_healthy_10"))
        empty!(q.diseases)
        row = tr_period!(r, m, 2)
        @test val(row, "healthy_healthy_10") == 0 && isnan(val(row, "healthy_healthy_10_strict"))
    end

    @testset "pairs and gaps, every tenth period" begin
        m = tr_market()
        a = tr_trader(m, 1, 1; sugar=5.0, spice=8.0)
        b = tr_trader(m, 1, 2; sugar=15.0, spice=2.0)
        c = tr_trader(m, 3, 3; sugar=10.0, spice=10.0)
        e = tr_trader(m, 3, 4; sugar=10.0, spice=10.0, sick=true)
        d = tr_trader(m, 4, 1; sugar=10.0, spice=10.0, sick=true)  # alone
        f = tr_trader(m, 2, 3; sugar=10.0, spice=8.0, sick=true)  # next to c; cured after period 1: recovering in 10
        r = TradeReadings(; window=(1, 10))
        rows = [
            tr_period!(r, m, t, () -> (t == 2 && empty!(f.diseases); t == 1 && bargain!(m, a, b))) for t in 1:10
        ]
        @test all(t -> all(k -> isnan(val(rows[t], k)), TR_TENTH), 1:9)
        row = rows[10]
        @test val(row, "recovering") == 1  # f
        # a-b, and c-f (a recovering agent counts as healthy); c-e is healthy-sick
        @test (val(row, "pairs_hh"), val(row, "pairs_hs"), val(row, "pairs_ss")) == (2, 1, 0)
        # strictly: a-b both strictly healthy; c-f (f recovering) and c-e (e sick) exactly one
        @test (val(row, "pairs_HH"), val(row, "pairs_HX")) == (1, 2)
        gap_ab = abs(log(mrs(a)) - log(mrs(b)))
        @test gap_ab > 0
        @test val(row, "gap_sick") ≈ abs(log(mrs(e)) - log(mrs(c)))  # e's one neighbour
        # a-b, b-a, c-e, and with the recovering f as a first agent and as a neighbour: f-c, c-f
        gap_cf = abs(log(mrs(c)) - log(mrs(f)))
        @test gap_cf ≈ log(1.25) && !(gap_cf ≈ gap_ab)
        @test val(row, "gap_healthy") ≈ sort([gap_ab, gap_ab, abs(log(mrs(c)) - log(mrs(e))), gap_cf, gap_cf])[3]
        gap_ce = abs(log(mrs(c)) - log(mrs(e)))
        @test !(val(row, "gap_healthy") ≈ sort([gap_ab, gap_ab, gap_ce])[2])  # f's gaps count: without them it would differ
        # the strict gap has the strictly healthy as first agents, whatever their neighbour: a-b, b-a, c-e, c-f, not f-c
        strict = sort([gap_ab, gap_ab, gap_ce, gap_cf])
        @test val(row, "gap_strict") ≈ (strict[2] + strict[3]) / 2
        @test !(val(row, "gap_strict") ≈ val(row, "gap_healthy"))
    end

    @testset "pairs and gaps leave out what has no MRS, and the walk is the mean distance" begin
        m = tr_market()
        a = tr_trader(m, 1, 1; sugar=5.0, spice=8.0)
        b = tr_trader(m, 1, 2; sugar=15.0, spice=0.0)  # no spice: no valid MRS
        a.moved_dist, b.moved_dist = 3.0, 0.0
        r = TradeReadings(; window=(1, 10))
        row = tr_period!(r, m, 10)
        @test val(row, "pairs_hh") == 1 && isnan(val(row, "gap_healthy")) && isnan(val(row, "gap_sick"))
        @test val(row, "pairs_HH") == 1 && val(row, "pairs_HX") == 0 && isnan(val(row, "gap_strict"))
        @test val(row, "walked") == 1.5
        @test isnan(val(tr_period!(TradeReadings(; window=(1, 10)), tiny_model(zeros(Int, 3, 3)), 1), "walked"))
    end

    @testset "the snapshot counts the exchanges and those with a partner with no disease" begin
        m = tr_market()
        a = tr_trader(m, 0, 0; sugar=5.0, spice=8.0)
        b = tr_trader(m, 0, 1; sugar=15.0, spice=2.0)
        f = tr_trader(m, 2, 0; sugar=5.0, spice=8.0)
        g = tr_trader(m, 2, 1; sugar=15.0, spice=2.0, sick=true)
        h = tr_trader(m, 4, 3; sugar=5.0, spice=8.0)  # never trades
        q = tr_trader(m, 0, 3; sugar=5.0, spice=8.0, sick=true)  # sick in period 1: recovering at the start and after
        u = tr_trader(m, 0, 4; sugar=15.0, spice=2.0)
        p = tr_trader(m, 3, 0; sugar=10.0, spice=10.0, sick=true)  # sick at the start, cured in the window's first period
        r = TradeReadings(; window=(3, 5))
        tr_period!(r, m, 1)
        empty!(q.diseases)
        tr_period!(r, m, 2)
        empty!(p.diseases)
        tr_period!(r, m, 3, () -> bargain!(m, f, g))
        tr_period!(r, m, 4, () -> (bargain!(m, a, b); bargain!(m, q, u)))
        @test isempty(agent_rows(r)[2])  # the window is not over
        tr_period!(r, m, 5, () -> bargain!(m, a, b))
        _, rows = agent_rows(r)
        by_id = Dict(Int(row[1]) => row for row in rows)
        # g was sick in the window; q and p were recovering, and with no active disease they are kept
        @test sort(collect(keys(by_id))) == sort([a.id, b.id, f.id, h.id, q.id, u.id, p.id])
        @test agent_val(by_id[a.id], "exchanges") == agent_val(by_id[a.id], "exchanges_healthy_partner") > 0
        @test agent_val(by_id[f.id], "exchanges") > 0 && agent_val(by_id[f.id], "exchanges_healthy_partner") == 0
        @test agent_val(by_id[h.id], "exchanges") == 0 && agent_val(by_id[h.id], "exchanges_healthy_partner") == 0
        # a recovering partner has no active disease, so it counts for u, and u counts for q
        @test agent_val(by_id[u.id], "exchanges") == agent_val(by_id[u.id], "exchanges_healthy_partner") > 0
        @test agent_val(by_id[q.id], "exchanges") == agent_val(by_id[q.id], "exchanges_healthy_partner") > 0
        flags(x) = (agent_val(by_id[x.id], "recovering_start"), agent_val(by_id[x.id], "recovering_in_window"))
        @test flags(q) == (1, 1)
        @test flags(p) == (0, 1)  # sick, not recovering, at the end of period 2
        @test all(x -> flags(x) == (0, 0), (a, b, f, h, u))
        # the strict snapshot, neither sick nor recovering at its start or in it, is those with both flags 0
        strict = [id for (id, row) in by_id
                  if agent_val(row, "recovering_start") == 0 && agent_val(row, "recovering_in_window") == 0]
        @test sort(strict) == sort([a.id, b.id, f.id, h.id, u.id])
        @test agent_val(by_id[a.id], "sugar_start") == 5.0 && agent_val(by_id[a.id], "sugar_end") == a.sugar != 5.0
    end

    @testset "on a VI-1 run: every row adds up" begin
        m, r, log, start_sick = tr_run(30)
        header, rows = trade_rows(r)
        @test header == TR_HEADER && length(rows) == 30 && [row[1] for row in rows] == 1.0:30.0
        last_sick = Dict{Int,Int}(id => 0 for id in start_sick)
        for (row, step) in zip(rows, log)
            # strictly healthy, from the log: no disease now and none in the last 10 periods
            foreach(id -> last_sick[id] = step.t, step.sick)
            strict(id, sick) = !sick && step.t - get(last_sick, id, -99) > 10
            both = [strict(x, sx) && strict(y, sy) for ((x, y), (sx, sy)) in zip(step.partners, step.partners_sick)]
            one = [strict(x, sx) != strict(y, sy) for ((x, y), (sx, sy)) in zip(step.partners, step.partners_sick)]
            @test val(row, "exchanges_HH") == count(both)
            @test val(row, "exchanges_HX") == count(one)
            @test val(row, "exchanges_HH") <= val(row, "exchanges_hh")
            @test val(row, "exchanges") == step.exchanges
            @test val(row, "exchanges") == val(row, "exchanges_hh") + val(row, "exchanges_hs") + val(row, "exchanges_ss")
            @test val(row, "healthy") + val(row, "recovering") + val(row, "sick") == step.n
            @test val(row, "sick") == length(step.sick)
            # a share of those with no disease (of the strictly healthy): undefined (NaN) in the first periods, when
            # everyone caught a founder's disease
            @test isnan(val(row, "healthy_healthy_10")) == (val(row, "healthy") + val(row, "recovering") == 0)
            @test isnan(val(row, "healthy_healthy_10")) || 0 <= val(row, "healthy_healthy_10") <= 1
            @test isnan(val(row, "healthy_healthy_10_strict")) == (val(row, "healthy") == 0)
            @test isnan(val(row, "healthy_healthy_10_strict")) || 0 <= val(row, "healthy_healthy_10_strict") <= 1
            @test val(row, "exchanges_recovering") <= val(row, "exchanges")
            @test val(row, "sick_traders") == step.sick_traders
            @test isequal(val(row, "walked"), step.walked)
            on_tenth = Int(row[1]) % 10 == 0
            if on_tenth
                @test all(k -> !isnan(val(row, k)), ("pairs_hh", "pairs_hs", "pairs_ss", "pairs_HH", "pairs_HX"))
                @test val(row, "pairs_HH") <= val(row, "pairs_hh")
                @test val(row, "pairs_HH") + val(row, "pairs_HX") <=
                      val(row, "pairs_hh") + val(row, "pairs_hs") + val(row, "pairs_ss")
            else
                @test all(k -> isnan(val(row, k)), TR_TENTH)
            end
        end
        @test sum(row -> val(row, "exchanges_HX"), rows) > 0
        @test any(row -> Int(row[1]) % 10 == 0 && !isnan(val(row, "gap_strict")) && val(row, "gap_strict") >= 0, rows)
        @test any(row -> val(row, "healthy_healthy_10") > 0, rows)
        @test any(row -> val(row, "healthy_healthy_10_strict") > 0, rows)
        @test any(row -> val(row, "walked") > 0, rows)  # the xxl agents walk
        @test sum(row -> val(row, "exchanges"), rows) > 0 && sum(row -> val(row, "sick"), rows) > 0
        @test any(row -> val(row, "recovering") > 0, rows) && any(row -> val(row, "exchanges_hs") > 0, rows)
        @test any(row -> Int(row[1]) % 10 == 0 && !isnan(val(row, "gap_healthy")) && val(row, "gap_healthy") >= 0, rows)
    end

    @testset "on a VI-1 run: the snapshot is who was alive with no disease throughout" begin
        m, r, log = tr_run(30)
        header, rows = agent_rows(r)
        @test header == TR_AGENT_HEADER && !isempty(rows) && all(row -> length(row) == 13, rows)
        ids = [Int(row[1]) for row in rows]
        @test issorted(ids) && allunique(ids)
        at(t) = log[t]
        # Sick in 21-30 is out; recovering in one of them (sick in the 10 periods before) is in, and flagged, as is
        # recovering at the end of period 20.
        last_sick = Dict{Int,Int}()
        out, recovered, at_start = Set{Int}(), Set{Int}(), Set{Int}()
        for step in log
            for id in step.sick
                last_sick[id] = step.t
            end
            recovering(id) = !(id in step.sick) && step.t - get(last_sick, id, -99) <= 10
            if step.t == 20
                foreach(id -> recovering(id) && push!(at_start, id), step.alive)
            elseif step.t >= 21
                for id in step.alive
                    id in step.sick && push!(out, id)
                    recovering(id) && push!(recovered, id)
                end
            end
        end
        took_part, well_partner = Dict{Int,Int}(), Dict{Int,Int}()
        for step in log[21:30], ((x, y), (sx, sy)) in zip(step.partners, step.partners_sick)
            took_part[x] = get(took_part, x, 0) + 1
            took_part[y] = get(took_part, y, 0) + 1
            sy || (well_partner[x] = get(well_partner, x, 0) + 1)
            sx || (well_partner[y] = get(well_partner, y, 0) + 1)
        end
        both = intersect(at(20).alive, at(30).alive)
        @test Set(ids) == setdiff(both, out)
        @test length(ids) < length(both)  # the sick were left out
        flagged = Set(Int(row[1]) for row in rows if agent_val(row, "recovering_in_window") == 1)
        @test flagged == intersect(Set(ids), recovered) && !isempty(flagged)  # recovering agents are kept
        @test Set(Int(row[1]) for row in rows if agent_val(row, "recovering_start") == 1) == intersect(Set(ids), at_start)
        for row in rows
            @test agent_val(row, "exchanges") == get(took_part, Int(row[1]), 0)
            @test agent_val(row, "exchanges_healthy_partner") == get(well_partner, Int(row[1]), 0)
            @test agent_val(row, "exchanges_healthy_partner") <= agent_val(row, "exchanges")
        end
        @test sum(row -> agent_val(row, "exchanges"), rows) <= sum(values(took_part))
        @test any(row -> agent_val(row, "exchanges") > 0, rows)
        by_id = Dict(a.id => a for a in m.agents)
        for row in rows
            a = by_id[Int(row[1])]
            @test row[2] == a.metabolism && row[3] == a.spice_metabolism && row[4] == a.vision
            @test row[8] == a.sugar && row[9] == a.spice
            @test row[5] + 10 == a.age  # 21 to 30 is ten periods older than the end of period 20
        end
    end

    @testset "meetings: runs of exchanges between the same two agents" begin
        m = tr_market()
        a, b = tr_trader(m, 0, 0; sugar=5.0, spice=8.0), tr_trader(m, 0, 1; sugar=15.0, spice=2.0)
        c, d = tr_trader(m, 2, 0; sugar=5.0, spice=8.0), tr_trader(m, 2, 1; sugar=15.0, spice=2.0)
        ex(p, x, y) = Exchange(p, 1.0, p, x, y)
        r = TradeReadings(; window=(1, 5))
        # three exchanges a-b, two c-d, one b-a later (the other agent's turn): three meetings
        row = tr_period!(r, m, 1, () -> append!(m.trade_log,
            [ex(2.0, a, b), ex(2.0, a, b), ex(2.0, a, b), ex(0.5, c, d), ex(0.5, c, d), ex(4.0, b, a)]))
        @test val(row, "exchanges") == 6 && val(row, "meetings") == 3
        prices = log.([2.0, 0.5, 4.0])
        mean = sum(prices) / 3
        @test val(row, "meeting_price_sd") ≈ sqrt(sum((prices .- mean) .^ 2) / 3)
        # a meeting's price is its first exchange's
        row = tr_period!(r, m, 2, () -> append!(m.trade_log, [ex(2.0, a, b), ex(3.0, a, b), ex(0.5, c, d)]))
        @test val(row, "meetings") == 2
        @test val(row, "meeting_price_sd") ≈ abs(log(2.0) - log(0.5)) / 2
        # one meeting or none: no sd
        row = tr_period!(r, m, 3, () -> append!(m.trade_log, [ex(2.0, a, b), ex(2.0, b, a)]))
        @test val(row, "meetings") == 1 && isnan(val(row, "meeting_price_sd"))
        row = tr_period!(r, m, 4)
        @test val(row, "meetings") == 0 && isnan(val(row, "meeting_price_sd"))
    end

    @testset "on a VI-1 run: meetings, with Rule 14 on and off" begin
        for (rule, one_price) in (("meeting", true), (nothing, false))
            m = Model(tr_config(; trade_price=rule))
            r = TradeReadings(; window=(21, 30))
            trade_period!(r, m)
            exchanges = meetings_total = mixed = 0
            for _ in 1:30
                step!(m)
                trade_period!(r, m)
                row = r.rows[end]
                meetings = Vector{Vector{Float64}}()
                last = nothing
                for e in m.trade_log
                    key = minmax(e.a.id, e.b.id)
                    key == last ? push!(meetings[end], e.price) : push!(meetings, [e.price])
                    last = key
                end
                @test val(row, "meetings") == length(meetings) <= val(row, "exchanges")
                # With Rule 14 on, a run holds one price, bar the odd run of two meetings: the pair's two turns can
                # come one right after the other, and the definition cannot tell them apart.
                mixed += count(p -> !all(==(p[1]), p), meetings)
                exchanges += length(m.trade_log)
                meetings_total += val(row, "meetings")
            end
            @test exchanges == sum(row -> val(row, "exchanges"), r.rows)
            @test meetings_total > 0
            one_price ? (@test mixed * 50 <= meetings_total) : (@test mixed > 0)  # prices vary within a meeting
        end
    end

    @testset "the snapshot of a window that starts at period 1 is taken before any step" begin
        vi1 = find_experiment(TR_REG, "VI-1")
        m = Model(replace_config(vi1.config; seed=vi1.config.seed, disease_list=0, diseases_per_agent=0))
        r = TradeReadings(; window=(1, 3))
        start = Dict(a.id => (a.sugar, a.spice, a.age) for a in m.agents)
        trade_period!(r, m)  # t = 0: nothing to read, the start to keep
        @test isempty(r.rows)
        for _ in 1:3
            step!(m)
            trade_period!(r, m)
        end
        _, rows = agent_rows(r)
        @test !isempty(rows) && length(r.rows) == 3
        for row in rows
            @test (row[6], row[7], row[5]) == start[Int(row[1])]
        end
    end

    @testset "the run is the same with the observer" begin
        vi1 = with_steps(find_experiment(TR_REG, "VI-1"), 30)
        plain, _ = Sugarscape.timed_seed(vi1, 0)
        r = TradeReadings(; window=(21, 30))
        watched, _ = Sugarscape.timed_seed(vi1, 0; trade_readings=r)
        @test isequal(plain, watched)
        @test length(r.rows) == 30 && !isempty(agent_rows(r)[2])
    end

    @testset "the xxl run is the same with the observer, through timed_seed and by hand" begin
        vi1 = find_experiment(TR_REG, "VI-1")
        cfg = tr_config()
        small = Experiment(vi1.id, vi1.title, vi1.rules, 30, vi1.seeds, cfg, vi1.fingerprint, vi1.xl_config, vi1.xl_fingerprint)
        plain, _ = Sugarscape.timed_seed(small, 0)
        r = TradeReadings(; window=(21, 30))
        watched, _ = Sugarscape.timed_seed(small, 0; trade_readings=r)
        @test isequal(plain, watched) && length(plain) == 31
        @test length(r.rows) == 30 && !isempty(agent_rows(r)[2])
        # step by hand, two models of one seed: the metrics and the random stream agree in every period
        seeded = replace_config(cfg; seed=cfg.seed)
        a, b = Model(seeded), Model(seeded)
        o = TradeReadings(; window=(21, 30))
        trade_period!(o, b)
        for _ in 1:30
            step!(a)
            step!(b)
            trade_period!(o, b)
            @test isequal(collect_metrics(a), collect_metrics(b)) && a.rng == b.rng
        end
        state(m) = [(x.id, x.x, x.y, x.sugar, x.spice, x.age) for x in m.agents]
        @test state(a) == state(b)
        # the same readings from stepping by hand
        _, by_hand, _ = tr_run(30)
        @test isequal(trade_rows(r)[2], trade_rows(by_hand)[2]) && isequal(agent_rows(r)[2], agent_rows(by_hand)[2])
    end

    @testset "not with a checkpoint" begin
        tiny = find_experiment(TR_REG, "TEST-tiny")
        checkpoint = (; restore=() -> nothing, period_done=(m, rows, clock) -> false)
        @test_throws ArgumentError Sugarscape.timed_seed(
            tiny, 0; xxl=XXL_V1, trade_readings=TradeReadings(; window=(1, 5)), checkpoint=checkpoint
        )
    end

    @testset "seed_job passes trade_readings only when it is set" begin
        tiny = find_experiment(TR_REG, "TEST-tiny")
        stand_in(exp, k; xl=false, xxl=nothing) = ([[0.0]], (; seed=k))
        @test Sugarscape.seed_job(tiny, 0, false, stand_in; xxl=XXL_BOOK)[1] == [[0.0]]
        with_readings(exp, k; xl=false, xxl=nothing, scorecard=false, trade_readings=nothing) =
            ([[trade_readings === nothing ? 0.0 : 1.0]], (; seed=k))
        r = TradeReadings(; window=(1, 5))
        @test Sugarscape.seed_job(tiny, 0, false, with_readings; xxl=XXL_BOOK, trade_readings=r)[1] == [[1.0]]
    end
end
