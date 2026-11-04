# xxl (stage 5): the trade report (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 1" and "Part 3").
# Hand-made study folders read into the report: the matched ratio, each screening bar at its edge, the choice and the
# result rows, Part 1's table, an extinct seed, the bars' text, the trade-off reading, confirmation and the command line.
using Sugarscape, Test

const TR_XXL = "xxl vision_shape=\"disc\" speed=(1, 6) travel_cost=0.2 free_step=1.5 disease_count=3 founder_diseases=1 " *
               "disease_lengths=(9, 10)"
const TR_CONFIG = "Config(width=500, spice=True, trade=True, credit=(10, 10.0), disease_list=25, diseases_per_agent=10, " *
                  "disease_length=(1, 10), immune_length=50, seed=0)"
const TR_SEED_COLUMNS = "t,population,agents_ever,fraction_sick,diseases_circulating,gini,mean_sugar,mean_spice,trades," *
                        "mean_price,price_sd,mean_moved"

"""
An agent snapshot of one matched cell of 6 (all starting with 10 sugar and 10 spice): the two with fewest exchanges end
with 10 sugar, the middle two with 10, the two with most with `10r`, so that its matched ratio is `r` at any price.
`vision` and `first` (the first id) set the cell apart from another, `recovering` the two recovering flags of all six.
"""
function tr_agents(r; vision=3, first=1, recovering=(0, 0))
    ends = [10.0, 10.0, 10.0, 10.0, 10r, 10r]
    return permutedims(hcat((Float64[first + i - 1, 2, 2, vision, 20, 10, 10, ends[i], 0, i - 1, 0, recovering...]
                             for i in 1:6)...))
end

"""
A study folder of `n` seeds under `dir/name` (first seed from the name's `-s<k>-`), shaped like `run_trade_arm`'s: a
fingerprint with `xxl` (the rules line, `settings` added at its end), `extra` (such as `trade: off`), the periods and the
readings' window (the last 20 periods unless `window` is given), and per seed its CSV, its trade readings and its agent
snapshot. Every keyword is a number held throughout, or a function of the seed's place (1, 2, ...) giving one; `pop`
and the CSV's other columns may also give a whole column (t = 0 to `periods`). The population is 2,000 at t = 0, `low`
(else `pop`) at t = 1 and `pop` after. The trade readings hold the same row every period, the pairs and gaps only at
every tenth: `hh`, `hs`, `ss`, `pairs` and `gaps` (healthy, sick) count a recovering agent as healthy, `HH`, `HX`,
`pairs_strict` (HH, HX) and `gap_strict` are the strictly healthy's. `agents` gives a seed's snapshot, else
`tr_agents(ratio)`.
"""
function tr_folder(dir, name; n=20, periods=500, window=nothing, xxl=TR_XXL, settings="", extra="", pop=1000.0,
                   low=nothing, sick=0.08, diseases=3.0, gini=0.3, sugar=40.0, spice=30.0, trades=1000.0, price=1.0,
                   price_sd=0.2, moved=1.5, healthy=900.0, sick_n=80.0, hh=600.0, hs=300.0, ss=100.0, hh10=0.3,
                   hh10_strict=0.2, HH=500.0, HX=400.0, pairs=(800.0, 150.0, 50.0), pairs_strict=(700.0, 200.0),
                   gaps=(0.1, 0.4), gap_strict=0.12, ratio=1.2, agents=nothing)
    folder = joinpath(dir, name)
    mkpath(folder)
    lo, hi = something(window, (max(1, periods - 19), periods))
    write(joinpath(folder, "fingerprint.txt"),
          "julia\n$xxl$(isempty(settings) ? "" : " " * settings)\nlook: centred\n({G1}, {M, S, K, T, L10,10, E})\n" *
          "steps=500\n$TR_CONFIG\nxl map sha256=xl-a\n" * (isempty(extra) ? "" : extra * "\n") *
          "code sha256=code-a\nperiods=$periods\ntrade readings: window=($lo, $hi)\n")
    first_seed = parse(Int, match(r"-s(\d+)-", name).captures[1])
    each(x, i) = x isa Function ? x(i) : x
    column(x) = x isa AbstractVector ? Float64.(x) : fill(Float64(x), periods + 1)
    for i in 1:n
        k = first_seed + i - 1
        p = each(pop, i)
        population = p isa AbstractVector ? Float64.(p) :
                     vcat(2000.0, Float64(something(each(low, i), p)), fill(Float64(p), periods - 1))
        cols = [population, 100.0 .+ (0:periods), (column(each(x, i)) for x in (sick, diseases, gini, sugar, spice, trades,
                                                                                price, price_sd, moved))...]
        write(joinpath(folder, "seed$k.csv"),
              TR_SEED_COLUMNS * "\n" * join(("$(t - 1)," * join((c[t] for c in cols), ",") * "\n" for t in 1:(periods + 1))))
        h, s, x, y, z = each(hh, i), each(hs, i), each(ss, i), each(pairs, i), each(gaps, i)
        g, q = each(gap_strict, i), each(pairs_strict, i)
        rows = map(1:periods) do t
            tenth = t % 10 == 0
            return Float64[t, each(healthy, i), 20, each(sick_n, i), h + s + x, h, s, x, 10, 70, each(hh10, i), 1.0,
                           (tenth ? y : (NaN, NaN, NaN))..., (tenth ? z : (NaN, NaN))..., each(hh10_strict, i),
                           each(HH, i), each(HX, i), (tenth ? (g, q...) : (NaN, NaN, NaN))...]
        end
        write(joinpath(folder, "seed$k-trade.csv"),
              join(Sugarscape.TRADE_COLUMNS, ",") * "\n" * join((join(r, ",") * "\n" for r in rows)))
        a = agents === nothing ? tr_agents(each(ratio, i)) : each(agents, i)
        write(joinpath(folder, "seed$k-agents.csv"),
              join(Sugarscape.TRADE_AGENT_COLUMNS, ",") * "\n" *
              join((join(a[r, :], ",") * "\n" for r in axes(a, 1))))
    end
    return folder
end

"""The xl reference: `n` seeds of VI-1 over 500 periods with an end price sd of `price_sd`."""
function tr_xl(dir; n=20, price_sd=0.2)
    folder = joinpath(dir, "scorecard-xl-s80-$n", "VI-1")
    mkpath(folder)
    write(joinpath(folder, "fingerprint.txt"), "julia\nxl\n")
    for k in 80:(80 + n - 1)
        write(joinpath(folder, "seed$k.csv"), "t,population,price_sd\n" * join(("$t,1000,$price_sd\n" for t in 0:500)))
    end
    return folder
end

# The last cell of the reading table's row `row` of arm `arm`: pass, near, fail or missing; absent with no such row.
function tr_result(report, arm, row)
    line = findfirst(l -> startswith(l, "| $arm | $row |"), split(report, "\n"))
    line === nothing && return "absent"
    return strip(split(split(report, "\n")[line], "|")[end - 1])
end

const TR_NODISEASE = replace(TR_XXL, "founder_diseases=1" => "founder_diseases=0")

@testset "trade report" begin
    dir = mktempdir()
    vi1(name; kw...) = tr_folder(dir, "trade-$name-VI-1-s80-20-p500"; kw...)
    nod(name; kw...) = tr_folder(dir, "trade-$name-nodisease-VI-1-s80-20-p500"; xxl=TR_NODISEASE, kw...)
    iva3(name; kw...) = tr_folder(dir, "trade-$name-IV-A3-s80-20-p300"; periods=300, kw...)
    study(name, folder) = Sugarscape.read_trade_run(name, folder)
    base_nod, arm_nod = study("today", nod("today"; trades=500.0)), study("A", nod("A"))  # 0.5 and 1.0 trades per head
    base_iva3 = study("today", iva3("today"))
    base = Sugarscape.TradeArm("today", study("today", vi1("today")), base_nod, base_iva3)
    off = study("today-off", vi1("today-off"; extra="trade: off", ratio=1.0, price=NaN))
    xl = Sugarscape.read_xl_prices(tr_xl(dir))
    arm(name; nodisease=arm_nod, kw...) = Sugarscape.TradeArm(name, study(name, vi1(name; kw...)), nodisease, base_iva3)
    screen(arms) = Sugarscape.trade_report(; label="t", base, arms, off, xl)

    @testset "matched ratio" begin
        # one cell of 6 agents (vision 3) and one of 4 (vision 4), all starting with 10 sugar and 10 spice
        row(id, vision, ex, sugar_end, spice_end) = permutedims(Float64[id, 2, 2, vision, 20, 10, 10, sugar_end, spice_end, ex, 0])
        rows = vcat(row(1, 3, 0, 5, 10), row(2, 3, 1, 5, 10),     # fewest exchanges: 5 + 10 / 2 = 10 at p̄ = 2
                    row(3, 3, 2, 8, 4), row(4, 3, 3, 8, 4),       # the middle third, not compared
                    row(5, 3, 4, 15, 10), row(6, 3, 5, 15, 10),   # most: 15 + 10 / 2 = 20
                    row(7, 4, 0, 1, 1), row(8, 4, 1, 1, 1), row(9, 4, 9, 99, 99), row(10, 4, 9, 99, 99))
        m = Sugarscape.matched_ratio(rows, 2.0)
        @test m.ratio ≈ 2.0 && m.kept == 6 && m.dropped == 4
        # resources are sugar + spice / p̄: at p̄ = 1 the top third ends with 25 and the bottom with 15
        @test Sugarscape.matched_ratio(rows, 1.0).ratio ≈ 25 / 15
        @test Sugarscape.matched_ratio(rows, 2.0; value=:raw).ratio ≈ 25 / 15
        w = Sugarscape.matched_ratio(rows, 2.0; value=:welfare)  # equal metabolisms: sqrt(sugar * spice)
        @test w.ratio ≈ sqrt(150) / sqrt(50) && w.kept == 6
        # ties in exchanges are broken by id, so the rows' order doesn't matter
        tied = vcat((row(i, 3, 3, i, 0) for i in 1:6)...)
        r = Sugarscape.matched_ratio(tied, 1.0).ratio
        @test r ≈ 5.5 / 1.5
        @test Sugarscape.matched_ratio(tied[[4, 1, 6, 3, 5, 2], :], 1.0).ratio == r
        @test Sugarscape.matched_ratio(rows[end:-1:1, :], 2.0).ratio == m.ratio
        # the cells are by quintile of start resources: ten agents starting apart fall in cells of 2, all dropped
        apart = vcat((permutedims(Float64[i, 2, 2, 3, 20, 10i, 0, 10i, 0, i, 0]) for i in 1:10)...)
        q = Sugarscape.matched_ratio(apart, 1.0)
        @test isnan(q.ratio) && q.kept == 0 && q.dropped == 10
        # and by age band: ages 20 and 29 share one, 30 doesn't
        ages = [20, 29, 25, 25, 25, 25, 30]
        aged = vcat((permutedims(Float64[i, 2, 2, 3, ages[i], 10, 10, 10, 0, i, 0]) for i in 1:7)...)
        a = Sugarscape.matched_ratio(aged, 1.0)
        @test a.kept == 6 && a.dropped == 1
        e = Sugarscape.matched_ratio(zeros(0, 13), 1.0)
        @test isnan(e.ratio) && e.kept == 0 && e.dropped == 0
        # two kept cells of different sizes, pooled by cell size: a cell of 6 (thirds of 2: 10 against 20) and one of
        # 7 (thirds of 2, the middle 3: 2 against 30). Σ n · mean is 6·20 + 7·30 over 6·10 + 7·2; pooling the agents (or
        # the cells' means) unweighted would give 100 / 24.
        ends6, ends7 = [10, 10, 15, 15, 20, 20], [2, 2, 9, 9, 9, 30, 30]
        two = vcat((row(i, 3, i, ends6[i], 0) for i in 1:6)..., (row(6 + i, 4, i, ends7[i], 0) for i in 1:7)...)
        w2 = Sugarscape.matched_ratio(two, 1.0)
        @test w2.kept == 13 && w2.dropped == 0
        @test w2.ratio ≈ (6 * 20 + 7 * 30) / (6 * 10 + 7 * 2)
        @test !(w2.ratio ≈ 100 / 24)
    end

    @testset "each bar at its edge" begin
        arms = [
            arm("r110"; ratio=1.1), arm("r109"; ratio=1.09), arm("r100"; ratio=1.0),
            arm("nd2"), arm("nd195"; nodisease=study("nd195", nod("nd195"; trades=950.0))),
            arm("nd18"; nodisease=study("nd18", nod("nd18"; trades=900.0))),
            arm("sick50"; hs=150.0, ss=50.0), arm("sick48"; hs=140.0, ss=50.0), arm("sick40"; hs=100.0, ss=50.0),
            arm("tr95"; low=950.0), arm("trnear"; low=i -> i == 1 ? 890.0 : 1000.0), arm("trfail"; low=900.0 * 0.95),
            arm("trmean"; low=940.0), arm("trboth"; low=i -> i == 1 ? 890.0 : 945.0),
            arm("x9at18"; diseases=i -> i <= 18 ? 3.0 : 0.0), arm("x9at17"; diseases=i -> i <= 17 ? 3.0 : 0.0),
            arm("x10at18"; sick=i -> i <= 18 ? 0.08 : 0.3), arm("x10at17"; sick=i -> i <= 17 ? 0.08 : 0.3),
            arm("x6at15"; price_sd=0.3), arm("x6near"; price_sd=0.31), arm("x6fail"; price_sd=0.4),
        ]
        r = screen(arms)
        @test tr_result(r, "r110", "Richer with trade") == "pass"
        @test tr_result(r, "r109", "Richer with trade") == "near"
        @test tr_result(r, "r100", "Richer with trade") == "fail"
        @test tr_result(r, "nd2", "Without disease") == "pass"
        @test tr_result(r, "nd195", "Without disease") == "near"
        @test tr_result(r, "nd18", "Without disease") == "fail"
        @test tr_result(r, "sick50", "Sick agents still trade") == "pass"
        @test tr_result(r, "sick48", "Sick agents still trade") == "near"
        @test tr_result(r, "sick40", "Sick agents still trade") == "fail"
        @test tr_result(r, "tr95", "Trough") == "pass"
        @test tr_result(r, "trnear", "Trough") == "near"  # the mean meets its bar, exactly one seed below
        @test tr_result(r, "trmean", "Trough") == "near"  # the mean 940, within 5% of 950, no seed below
        @test tr_result(r, "trboth", "Trough") == "fail"  # the mean 942.25 short and one seed below: both miss
        @test tr_result(r, "trfail", "Trough") == "fail"  # every seed below 90% of today's lowest
        @test tr_result(r, "x9at18", "Disease: X9") == "pass"
        @test tr_result(r, "x9at17", "Disease: X9") == "near"
        @test tr_result(r, "x10at18", "Disease: X10 per seed") == "pass"
        @test tr_result(r, "x10at17", "Disease: X10 per seed") == "near"
        @test tr_result(r, "x6at15", "Prices: X6") == "pass"
        @test tr_result(r, "x6near", "Prices: X6") == "near"
        @test tr_result(r, "x6fail", "Prices: X6") == "fail"
        @test tr_result(r, "r110", "Extinction") == "pass"
        # every arm has every row, and only the four arms made to fail the trough fail it
        for a in arms, row in ("Richer with trade", "Without disease", "Sick agents still trade",
                               "Trough", "Disease: X9", "Disease: X10 per seed", "Prices: X6", "Extinction")
            res = tr_result(r, a.name, row)
            @test res in ("pass", "near", "fail")
        end
        # the healthy-trade bar is dropped (the user's): no arm has the row
        @test all(a -> tr_result(r, a.name, "Healthy trade") == "absent", arms)
        @test count(a -> tr_result(r, a.name, "Trough") == "pass", arms) == length(arms) - 4
        # with arms passing, one is chosen and no near arm is offered
        @test occursin("Chosen: ", r) && !occursin("Near passing", r)
    end

    @testset "the bars as printed" begin
        r = screen([arm("A")])
        @test occursin("at least 1.10, its 95% interval above 1", r)
        @test !occursin("| A | Healthy trade |", r) && !occursin("agents with no disease, t = 451", r)
        # the bar's ratio is the strictly healthy's; the wider one, recovering included, is printed beside it
        @test occursin("| A | Richer with trade | 1.2, interval [1.2, 1.2] (recovering included: 1.2, a reading) |", r)
        @test occursin("| Traders ÷ similar non-traders, recovering included, resources at p̄ |", r)
        # the healthy trade stays as a reading, both ways
        @test occursin("| Strictly healthy agents with a strictly healthy partner in 10 periods, t = 451–500 | 0.2 |", r)
        @test occursin("| The same, agents with no disease with a partner with none (recovering included) | 0.3 |", r)
        @test occursin("at least ×2 today's", r) && occursin("at least ×0.5 today's", r)
        @test occursin("mean at least 95% of today's", r) && occursin("none below 90% of today's lowest", r)
        @test occursin("at most 1.5", r) && occursin("at least 18 of 20", r)
        # the text comes from the constants
        @test occursin("at least $(Sugarscape.two_places(Sugarscape.RICHER_BAR)),", r)
        # the sick agents' reading names its bias, and healthy is said to be strictly healthy
        @test occursin("died later in the same period", r)
        @test occursin("healthy means strictly healthy (no disease for 10 periods) in every bar and Part 1 word, " *
                       "by the user's decision after Part 1", r)
        # the snapshot's window is read from the fingerprint: the last 20 periods, and IV-A3's
        @test occursin("the snapshot's window, t = 481–500", r) && occursin("IV-A3 is read over t = 281–300", r)
        @test !occursin("last 100 (its snapshot", r)
    end

    @testset "the Richer bar reads the strictly healthy, and a missing ratio decides nothing" begin
        # a cell of 6 strictly healthy agents and one of 6 recovering in the window (vision 4)
        mix(strict, recovering; flags=(0, 1)) = vcat(tr_agents(strict), tr_agents(recovering; vision=4, first=7, recovering=flags))
        r = screen([arm("strict-fails"; agents=mix(1.0, 2.0)), arm("strict-passes"; agents=mix(1.2, 0.5; flags=(1, 0)))])
        @test tr_result(r, "strict-fails", "Richer with trade") == "fail"  # recovering included it would be 1.5
        @test occursin("| strict-fails | Richer with trade | 1, interval [1, 1] (recovering included: 1.5, a reading) |", r)
        @test tr_result(r, "strict-passes", "Richer with trade") == "pass"  # recovering included it would be 0.85
        @test occursin("Chosen: strict-passes.", r)
        # the choice ranks by the strict ratio: 1.3 strictly beats 1.2, though the wider ones are 1.05 and 1.6
        c = screen([arm("wide"; agents=mix(1.2, 2.0)), arm("tight"; agents=mix(1.3, 0.8))])
        @test occursin("Chosen: tight.", c)
        # no seed with a matched cell: the row reads missing, not fail, and the arm can't pass or be near
        none = screen([arm("none"; agents=zeros(0, 13)), arm("A")])
        @test tr_result(none, "none", "Richer with trade") == "missing"
        @test occursin("**The matched ratio of none is missing: no seed has a matched cell, so its Richer with trade " *
                       "row reads missing and it can't pass.**", none)
        @test occursin("Chosen: A. Passing: A.", none)
        @test occursin("| none | Richer with trade | —, no seed has a matched cell (recovering included: —, a reading) |", none)
        @test !occursin("of none leaves out seed", none)  # the missing line says it once, not seed by seed
        # one seed without a cell is named, and the ratio reads the other 19
        one = screen([arm("one"; agents=i -> i == 1 ? zeros(0, 13) : tr_agents(1.2))])
        @test occursin("**The matched ratio of one leaves out seed 80 has no matched cell (cells of at least 6 strictly " *
                       "healthy agents).**", one)
        @test tr_result(one, "one", "Richer with trade") == "pass" && !occursin("of one is missing", one)
        alone = screen([arm("none"; agents=zeros(0, 13))])
        @test occursin("No arm passes. No arm is near.", alone)
        # a recovering-only snapshot is missing too: the bar reads none of it
        @test tr_result(screen([arm("rec"; agents=tr_agents(1.5; recovering=(0, 1)))]), "rec", "Richer with trade") == "missing"
    end

    @testset "the choice and the result rows" begin
        # the largest matched ratio first
        r = screen([arm("small"; ratio=1.3), arm("big"; ratio=1.5)])
        @test occursin("Chosen: big. Passing: small, big.", r) && occursin("take the choice to confirmation", r)
        # then the smallest rise in Gini, then the higher trough, then the simpler rule
        @test occursin("Chosen: flat.", screen([arm("rise"; gini=0.32), arm("flat"; gini=0.31)]))
        @test occursin("Chosen: high.", screen([arm("deep"; low=980.0), arm("high"; low=990.0)]))
        rule(name, s) = arm(name; settings=s)
        simple = screen([rule("half", "trade_move=\"local\" trade_blend=0.5 trade_guard=5"),
                         rule("local", "trade_move=\"local\" trade_guard=5"),
                         rule("own", "trade_move=\"own\" trade_guard=5")])
        @test occursin("Chosen: own.", simple)
        @test occursin("| half | local, blend 0.5, guard 5 |", simple) && occursin("| own | own, blend 1, guard 5 |", simple)
        @test occursin("Chosen: local.", screen([rule("half", "trade_move=\"local\" trade_blend=0.5 trade_guard=5"),
                                                  rule("local", "trade_move=\"local\" trade_guard=5")]))
        # a near arm and none passing: one further round; none near: stop
        near = screen([arm("n"; ratio=1.09)])
        @test occursin("No arm passes. Near passing: n (Richer with trade).", near)
        @test occursin("One further round of at most 3 arms", near) && !occursin("Chosen", near)
        far = screen([arm("f"; ratio=1.0, hh10=0.1)])
        @test occursin("No arm passes. No arm is near.", far) && occursin("Stop.", far) && occursin("No confirmation run", far)
        # with the healthy-trade bar dropped, little healthy trade doesn't stop an arm
        @test occursin("Chosen: quiet.", screen([arm("quiet"; hh10=0.01, hh10_strict=0.01)]))
        # trades that rise without healthy agents getting richer are said plainly
        busy = screen([arm("busy"; ratio=1.0, trades=1500.0)])
        @test occursin("busy: trades per head rise", busy) && occursin("more trade isn't the goal", busy)
        @test !occursin("trades per head rise", screen([arm("A")]))
        # a rise in Gini beyond 0.03 is said up front; 0.03 itself is not
        up = screen([arm("up"; gini=0.34), arm("edge"; gini=0.33)])
        @test occursin("**Gini rises by 0.04 in up", up) && !occursin("in edge", up)
        @test findfirst("**Gini rises", up).start < findfirst("## Arms", up).start
    end

    @testset "Part 1's table" begin
        d(; kw...) = Sugarscape.part1_decision(; ratio=1.0, lo=0.95, healthy_trade=0.1, sick_share=0.6, gap_ratio=0.4, kw...)
        @test d(; ratio=1.2, lo=1.05, healthy_trade=0.3).row == 1                  # the premise is wrong
        @test d(; ratio=1.2, lo=1.05).row == 2                                     # richer by selling to the sick
        @test d().row == 3 && d(; gap_ratio=0.5).row == 3                          # the diagnosis holds; 0.5 is small
        @test d(; gap_ratio=0.51).row == 4                                         # half right
        @test d(; sick_share=0.5).row == 5                                         # half is not more than half
        @test d(; ratio=1.2, lo=1.05, sick_share=0.3).row === nothing             # richer, but no row says so
        @test !d(; ratio=1.2, lo=1.0).words.richer && d(; ratio=1.1, lo=1.01).words.richer
        @test d(; healthy_trade=0.25).words.common && !d(; healthy_trade=0.2499).words.common
        # a missing ratio decides nothing: no row, though without it row 3 (or 1) would hold
        @test d().decided && d(; ratio=1.2, lo=1.05).decided
        @test !d(; ratio=NaN, lo=NaN).decided && d(; ratio=NaN, lo=NaN).row === nothing
        @test d(; ratio=NaN, lo=NaN, healthy_trade=0.3).row === nothing
        @test d(; ratio=NaN, lo=NaN).missing == [:richer] && isempty(d().missing)
        # so does any word's figure: each named, no row (row 3 would hold without the missing one)
        for (k, kw) in ((:common, (; healthy_trade=NaN)), (:mostly_sick, (; sick_share=NaN)), (:small, (; gap_ratio=NaN)))
            x = d(; kw...)
            @test !x.decided && x.row === nothing && x.missing == [k]
        end
        @test d(; ratio=NaN, lo=NaN, gap_ratio=NaN).missing == [:richer, :small]

        part1(name; kw...) = Sugarscape.trade_report(; label="p", part1=true, off, xl,
            base=Sugarscape.TradeArm("today", study(name, vi1(name; kw...)), base_nod, base_iva3))
        wrong = part1("p1wrong"; hh10_strict=0.3)  # ratio 1.2, 30% of the strictly healthy with a strictly healthy partner
        @test occursin("The premise is wrong. Stop and report", wrong)
        # 900 ÷ (900 + 600) of the strictly healthy's exchanges with a partner who isn't strictly healthy
        holds = part1("p1holds"; ratio=1.0, hh10_strict=0.1, HH=300.0, HX=900.0, hh=300.0, hs=900.0)
        @test occursin("The diagnosis holds. Go on to Part 2", holds)
        @test occursin("| Strictly healthy agents' exchanges with a partner not strictly healthy | 0.6 |", holds)
        @test occursin("| The same, recovering included: healthy agents' exchanges with a sick partner | 0.6 |", holds)
        # recovering agents are a group of their own: 20 of 1,000 agents, 10 exchanges with one among them
        @test occursin("| Recovering agents: share of agents / exchanges with one per recovering agent | 0.02 / 0.5 |", holds)
        # "small" reads the strict gap ÷ the sick one: 0.3 ÷ 0.4, though recovering included it is 0.1 ÷ 0.4
        half = part1("p1half"; ratio=1.0, hh10_strict=0.1, HH=300.0, HX=900.0, gap_strict=0.3)
        @test occursin("only half right: something besides movement", half)
        @test occursin("the strictly healthy median |log MRS gap| ÷ the sick one is 0.75, against at most 0.5: no. " *
                       "Recovering included, a reading: 0.25", half)
        # "mostly with sick partners" reads the strict share: 300 ÷ 1,500, though recovering included it is 0.6
        wide = part1("p1wide"; ratio=1.0, hh10_strict=0.1, hh=300.0, hs=900.0, HH=600.0, HX=300.0)
        @test occursin("Healthy agents trade with each other, but it doesn't pay", wide) && !occursin("diagnosis holds", wide)
        # Part 1 says whether today already meets the Richer bar; the healthy-trade bar is gone
        @test occursin("Today already meets the Richer with trade bar", wrong)
        @test !occursin("Today already meets", holds) && occursin("Today doesn't meet the Richer with trade bar", holds)
        @test !occursin("Healthy trade bar", wrong)
        @test occursin("## Trade on ÷ off", wrong) && occursin("## Traders against similar non-traders", wrong)
        # "common" reads the strict share against 25%; the wider one is beside it and decides nothing
        @test occursin("**common**: 0.3 of strictly healthy agents traded with a strictly healthy partner in the last " *
                       "10 periods, t = 451–500, against at least 25%: yes. Recovering included, a reading: 0.3", wrong)
        @test occursin("The premise is wrong", part1("p1strict"; hh10=0.1, hh10_strict=0.3))
        not_common = part1("p1loose"; hh10=0.3, hh10_strict=0.1)  # richer, not common, not mostly with sick partners
        @test occursin("No row of the table fires: healthy agents are richer with trade, but", not_common)
        @test occursin("| today | sugar + spice ÷ p̄, recovering included (a reading) |", wrong)
        @test occursin("healthy means strictly healthy (no disease for 10 periods) in every bar and Part 1 word", wrong)
        # no seed with a matched cell: said up front, no row fires
        none = part1("p1none"; agents=zeros(0, 13), hh10_strict=0.3)
        msg = "**The matched ratio is missing: no seed has a matched cell, so Part 1's decision can't be made and no " *
              "row of its table fires.**"
        @test occursin(msg, none) && findfirst(msg, none).start < findfirst("## Runs", none).start
        @test !occursin("The row that fires", none) && !occursin("premise is wrong", none)
        @test occursin("No row of the table fires: the matched ratio is missing, so the decision can't be made.", none)
        @test occursin("against at least 1.10 with its interval above 1: missing", none)
        @test occursin("Whether today meets the Richer with trade bar can't be said: the matched ratio is missing.", none)
        # each other word's figure missing: said up front, named, no row fires (row 5 would without it)
        @test occursin("Healthy agents trade with each other, but it doesn't pay", part1("p1all"; ratio=1.0))
        for (name, kw, figure) in (
                ("p1nocommon", (; hh10_strict=NaN),
                 "the share of strictly healthy agents with a strictly healthy partner (\"common\")"),
                ("p1nosick", (; HH=0.0, HX=0.0),
                 "the share of strictly healthy agents' exchanges with a partner who isn't (\"mostly with sick partners\")"),
                ("p1nogap", (; gap_strict=NaN), "the strictly healthy MRS gap ratio (\"small\")"))
            r = part1(name; ratio=1.0, kw...)
            line = "**$(uppercasefirst(figure)) is missing, so Part 1's decision can't be made and no row of its table fires.**"
            @test occursin(line, r) && findfirst(line, r).start < findfirst("## Runs", r).start
            @test !occursin("The row that fires", r) && !occursin("doesn't pay", r)
            @test occursin("No row of the table fires: $figure is missing, so the decision can't be made.", r)
            @test occursin(": missing. Recovering included", r)  # the word itself reads missing
            @test !occursin("Whether today meets", r) && occursin("Today doesn't meet the Richer with trade bar", r)
        end
    end

    @testset "the matched ratio over the strictly healthy" begin
        # a second cell of 6 (vision 4) at ratio 2, every agent of it recovering in the window: the bar's ratio pools
        # both cells, (6·12 + 6·20) ÷ (6·10 + 6·10); the strict reading has the first cell alone
        rows = vcat(tr_agents(1.2), tr_agents(2.0; vision=4, first=7, recovering=(0, 1)))
        @test size(Sugarscape.strict_rows(rows), 1) == 6
        @test size(Sugarscape.strict_rows(vcat(tr_agents(1.2), tr_agents(2.0; vision=4, first=7, recovering=(1, 0)))), 1) == 6
        mixed = study("mixed", vi1("mixed"; agents=rows))
        @test Sugarscape.matched_over_seeds(mixed).ratio ≈ 192 / 120
        @test Sugarscape.matched_over_seeds(mixed; strict=true).ratio ≈ 1.2
    end

    @testset "p̄ is the mean price over the snapshot's window" begin
        # the price is 5 before t = 481 and 2 over the window, t = 481–500. Every agent starts with 10 and 10; the
        # third with fewest exchanges ends with 10 sugar, the third with most with 20 spice: 20 / 2 = 10, a ratio of 1
        # at the window's price (0.41 at the whole run's mean price, 0.4 at 5)
        price = vcat(fill(5.0, 481), fill(2.0, 20))
        ends = [(10.0, 0.0), (10.0, 0.0), (10.0, 0.0), (10.0, 0.0), (0.0, 20.0), (0.0, 20.0)]
        agents = permutedims(hcat((Float64[i, 2, 2, 3, 20, 10, 10, ends[i]..., i - 1, 0, 0, 0] for i in 1:6)...))
        windowed = study("pbar", vi1("pbar"; price, agents))
        s = windowed.seeds[1]
        @test windowed.window == (481, 500) && Sugarscape.window_price(s, windowed.window...) == 2.0
        # read from the fingerprint, not assumed: a folder whose readings name another window is read over it
        other = study("pbar-other", vi1("pbar-other"; price, agents, window=(401, 500)))
        @test other.window == (401, 500) && Sugarscape.window_price(other.seeds[1], other.window...) ≈ (80 * 5 + 20 * 2) / 100
        @test Sugarscape.matched_over_seeds(windowed).ratio ≈ 1.0
        @test Sugarscape.matched_over_seeds(windowed; value=:raw).ratio ≈ 2.0
    end

    @testset "trade on ÷ off values the spice at the on run's p̄" begin
        # on: the snapshot's agents end with 10 sugar and 10 spice, at p̄ = 2 over the window (5 before it), so 15;
        # off: 10 sugar and no spice, 10. Leaving out the spice would give 1, the whole run's price 1.2
        price = vcat(fill(5.0, 481), fill(2.0, 20))
        holding(sugar, spice) = permutedims(hcat((Float64[i, 2, 2, 3, 20, 10, 10, sugar, spice, i - 1, 0, 0, 0] for i in 1:6)...))
        on = study("spice-on", vi1("spice-on"; price, agents=holding(10.0, 10.0)))
        off_run = study("spice-off", vi1("spice-off"; extra="trade: off", price=NaN, agents=holding(10.0, 0.0)))
        readings = Dict(Sugarscape.on_off(on, off_run))
        @test readings["Strictly healthy agents' mean resources at t = 500"].ratio ≈ 1.5
        @test readings["The same, recovering included (a reading)"].ratio ≈ 1.5
        @test readings["Population"].ratio ≈ 1.0
        # the strict reading leaves out the recovering: six more agents on, recovering in the window, with 30 sugar.
        # Strictly 15 ÷ 10; recovering included (6·15 + 6·30) ÷ 12 = 22.5 against 10
        recovering = holding(30.0, 0.0)
        recovering[:, 1] .+= 6
        recovering[:, 13] .= 1
        mixed = study("spice-mixed", vi1("spice-mixed"; price, agents=vcat(holding(10.0, 10.0), recovering)))
        both = Dict(Sugarscape.on_off(mixed, off_run))
        @test both["Strictly healthy agents' mean resources at t = 500"].ratio ≈ 1.5
        @test both["The same, recovering included (a reading)"].ratio ≈ 2.25
    end

    @testset "an extinct seed" begin
        gone = arm("gone"; pop=i -> i == 1 ? vcat(fill(1000.0, 200), zeros(301)) : 1000.0,
                   agents=i -> i == 1 ? zeros(0, 13) : tr_agents(1.2))
        m = Sugarscape.matched_over_seeds(gone.vi1)
        @test m.left_out == ["seed 80 went extinct at t = 200"] && length(m.per_seed) == 19 && m.kept == 19 * 6
        @test m.ratio ≈ 1.2
        r = screen([gone])
        @test occursin("**Seed 80 of gone, VI-1 went extinct at t = 200", r)
        # one extinct seed misses the row by one seed: near (here the trough is near too, its lowest 0, so the arm isn't)
        @test tr_result(r, "gone", "Extinction") == "near" && tr_result(r, "gone", "Richer with trade") == "pass"
        @test !occursin("NaN", r)
        two = arm("two"; pop=i -> i <= 2 ? vcat(fill(1000.0, 200), zeros(301)) : 1000.0,
                  agents=i -> i <= 2 ? zeros(0, 13) : tr_agents(1.2))
        @test tr_result(screen([two]), "two", "Extinction") == "fail"
        # an extinct IV-A3 seed: left out of its trades per head and price, 0 in its end population, as S5 reads it
        iva3_gone = study("iva3-gone", iva3("iva3-gone"; pop=i -> i == 1 ? vcat(fill(1000.0, 100), zeros(201)) : 1000.0,
                                            agents=i -> i == 1 ? zeros(0, 13) : tr_agents(1.2)))
        a3 = Sugarscape.TradeArm("a3", study("a3", vi1("a3")), arm_nod, iva3_gone)
        f = Sugarscape.arm_figures(a3, xl)
        @test f.iva3_end ≈ 19 * 1000 / 20 && length(f.per_seed.iva3_end) == 20 && length(f.per_seed.iva3_tph) == 19
        r3 = screen([a3])
        @test occursin("**Seed 80 of a3, IV-A3 went extinct at t = 100: it is left out of IV-A3's trades per head and " *
                       "mean price, and counts in its end population with what it has there, 0 once it died out", r3)
        @test !occursin("a3, IV-A3 went extinct at t = 100: it is left out of every ratio", r3)
        # an unfinished seed: the arm is flagged and can't be chosen
        short = arm("short")
        folder = joinpath(dir, "trade-short-VI-1-s80-20-p500")
        rm(joinpath(folder, "seed99.csv"))
        short = Sugarscape.TradeArm("short", study("short", folder), arm_nod, base_iva3)
        rs = screen([short])
        @test occursin("**Unfinished: 1 of 20 seeds of short, VI-1", rs) && occursin("No arm passes.", rs)
    end

    @testset "trade on ÷ off" begin
        r = screen([arm("A")])
        # healthy agents end with 64 / 6 on and 10 off, valued at the on run's price; the same population
        @test occursin("| today | Strictly healthy agents' mean resources at t = 500 | 1.067 |", r)
        @test occursin("| today | The same, recovering included (a reading) | 1.067 |", r)
        @test occursin("| today | Population | 1 |", r)
        @test !occursin("has trade on", r)
        on_off = Sugarscape.trade_report(; label="t", base, arms=[arm("A")], off=base.vi1, xl)
        @test occursin("**The trade-off folder trade-today-VI-1-s80-20-p500 has trade on", on_off) && occursin("has trade on", on_off)
        # an off folder with seed 80 extinct from t = 200 and seed 99 unfinished: both named, in all three modes
        name = "trade-gone-off-VI-1-s80-20-p500"
        folder = tr_folder(dir, name; extra="trade: off", ratio=1.0, price=NaN,
                           pop=i -> i == 1 ? vcat(fill(1000.0, 200), zeros(301)) : 1000.0,
                           agents=i -> i == 1 ? zeros(0, 13) : tr_agents(1.0))
        rm(joinpath(folder, "seed99.csv"))
        gone_off = study("gone-off", folder)
        reports = [Sugarscape.trade_report(; label="t", base, arms=[arm("A")], off=gone_off, xl),
                   Sugarscape.trade_report(; label="p", part1=true, base, off=gone_off, xl),
                   Sugarscape.trade_report(; label="c", confirm=true, off=gone_off,
                                           base=Sugarscape.TradeArm("A", base.vi1, nothing, nothing))]
        for g in reports
            @test occursin("**Unfinished: 1 of 20 seeds of the trade-off run ($name) have not run.", g)
            @test occursin("**Seed 80 of the trade-off run ($name) went extinct at t = 200: it is left out of trade on ÷ off.**", g)
            @test !occursin("has trade on", g) && !occursin("NaN", g)
        end
    end

    @testset "confirmation" begin
        confirm(ratio) = Sugarscape.trade_report(; label="c", confirm=true, off,
            base=Sugarscape.TradeArm("A", study("c$ratio", vi1("c$ratio"; ratio)), nothing, nothing))
        yes, no = confirm(1.2), confirm(1.0)
        @test tr_result(yes, "A", "Richer with trade") == "pass" && occursin("The ratio passes again", yes)
        @test tr_result(no, "A", "Richer with trade") == "fail" && occursin("not confirmed", no)
        @test occursin("## Trade on ÷ off", yes)
        # a missing ratio is said, and neither passes nor fails
        gone = Sugarscape.trade_report(; label="c", confirm=true, off,
            base=Sugarscape.TradeArm("A", study("cnone", vi1("cnone"; agents=zeros(0, 13))), nothing, nothing))
        @test tr_result(gone, "A", "Richer with trade") == "missing"
        @test occursin("The ratio is missing: no seed has a matched cell, so it can't be read, pass or fail.", gone)
        @test !occursin("passes again", gone) && !occursin("not confirmed", gone)
        # an unfinished study run is not read, pass or fail
        for ratio in (1.2, 1.0)
            folder = vi1("cu$ratio"; ratio)
            rm(joinpath(folder, "seed99.csv"))
            u = Sugarscape.trade_report(; label="c", confirm=true, off,
                base=Sugarscape.TradeArm("A", study("cu$ratio", folder), nothing, nothing))
            @test occursin("The study run is unfinished, so the ratio is not read", u)
            @test !occursin("fails on the new seeds", u) && !occursin("passes again", u)
        end
    end

    @testset "the xl reference reads whole seeds only" begin
        xdir = mktempdir()
        folder = tr_xl(xdir)
        write(joinpath(folder, "seed99.csv"), "t,population,price_sd\n" * join(("$t,1000,9\n" for t in 0:300)))  # cut short
        x = Sugarscape.read_xl_prices(folder)
        @test x.partial == [99] && length(x.prices) == 19 && all(==(0.2), x.prices)
        r = Sugarscape.trade_report(; label="t", base, arms=[arm("A")], off, xl=x)
        @test occursin("**The xl reference scorecard-xl-s80-20/VI-1 has seeds that aren't whole, left out of X6: 99.**", r)
        @test !occursin("aren't whole", screen([arm("A")]))
        # a folder of other periods beside the scorecard's names them: -p4 is t = 0 to 4
        short = joinpath(xdir, "scorecard-xl-s80-2-p4", "VI-1")
        mkpath(short)
        write(joinpath(short, "seed80.csv"), "t,price_sd\n" * join(("$t,0.5\n" for t in 0:4)))
        write(joinpath(short, "seed81.csv"), "t,price_sd\n" * join(("$t,0.5\n" for t in 0:500)))
        s = Sugarscape.read_xl_prices(short)
        @test s.prices == [0.5] && s.partial == [81]
        rm(joinpath(short, "seed80.csv"))
        @test_throws ArgumentError Sugarscape.read_xl_prices(short)  # no whole seed
    end

    @testset "screening refuses an arm on other seeds" begin
        for (name, folder) in (("s81", "trade-s81-VI-1-s81-20-p500"), ("n19", "trade-n19-VI-1-s80-19-p500"),
                               ("p600", "trade-p600-VI-1-s80-20-p600"))
            n = name == "n19" ? 19 : 20
            periods = name == "p600" ? 600 : 500
            other = Sugarscape.TradeArm(name, study(name, tr_folder(dir, folder; n, periods)), arm_nod, base_iva3)
            @test_throws ArgumentError screen([other])
        end
        nd19 = study("nd19", tr_folder(dir, "trade-nd19-nodisease-VI-1-s80-19-p500"; n=19, xxl=TR_NODISEASE))
        @test_throws ArgumentError screen([arm("A"; nodisease=nd19)])
        iva3_81 = study("i81", tr_folder(dir, "trade-i81-IV-A3-s81-20-p300"; periods=300))
        @test_throws ArgumentError screen([Sugarscape.TradeArm("i81", study("A", vi1("A")), arm_nod, iva3_81)])
        msg = try
            screen([Sugarscape.TradeArm("s81", study("s81", joinpath(dir, "trade-s81-VI-1-s81-20-p500")), arm_nod, base_iva3)])
            ""
        catch e
            e.msg
        end
        @test occursin("covers seeds 81 to 100 over 500 periods, not the baseline's 80 to 99 over 500", msg)
        # the same seeds and periods, but the snapshot read over another window (an older folder)
        old = Sugarscape.TradeArm("old", study("old", tr_folder(dir, "trade-old-VI-1-s80-20-p500"; window=(401, 500))),
                                  arm_nod, base_iva3)
        msg = try
            screen([old])
            ""
        catch e
            e.msg
        end
        @test occursin("reads its snapshot over t = 401–500, not the baseline's t = 481–500", msg)
    end

    @testset "folders it can't read" begin
        short = tr_folder(dir, "trade-p100-VI-1-s80-20-p100"; periods=100)
        @test_throws ArgumentError Sugarscape.trade_report(; label="t", base, off,  xl,
            arms=[Sugarscape.TradeArm("p100", study("p100", short), arm_nod, base_iva3)])
        plain = joinpath(dir, "extinction-plain-s80-1-p500")
        mkpath(plain)
        write(joinpath(plain, "fingerprint.txt"), "julia\n$TR_XXL\n$TR_CONFIG\nperiods=500\n")
        @test_throws ArgumentError study("plain", plain)  # no trade readings
    end

    @testset "the command line" begin
        usage(args) = redirect_stderr(() -> Sugarscape.trade_report_main(args), devnull)
        @test usage(["--nope"]) == 2
        @test usage(["--off", "x", "--xl", "y"]) == 2                     # screening without --base and --arms
        @test usage(["--part1", "--on", "a", "--off", "b"]) == 2          # Part 1 without the rest
        @test usage(["--confirm", "--vi1", "a", "--off", "b", "--xl", "c"]) == 2  # --xl isn't confirmation's
        a = Sugarscape.trade_report_args(["--base", "today=v,n,i", "--arms", "A=va,na,ia,B=vb,nb,ib", "--off", "o",
                                          "--xl", "x", "--out", "dir"])
        @test a.mode == :screen && a.base == ("today" => ["v", "n", "i"]) && a.label == "screen" && a.out == "dir"
        @test a.arms == ["A" => ["va", "na", "ia"], "B" => ["vb", "nb", "ib"]] && a.folders["off"] == "o"
        @test_throws ArgumentError Sugarscape.trade_report_args(["--base", "t=v,n", "--arms", "A=a,b,c", "--off", "o", "--xl", "x"])
        @test_throws ArgumentError Sugarscape.trade_report_args(["--base", "t=v,n,i", "--arms", "t=a,b,c", "--off", "o", "--xl", "x"])
        @test_throws ArgumentError Sugarscape.trade_report_args(["--base", "t=v,n,i", "--arms", "a,b,c", "--off", "o", "--xl", "x"])
        p = Sugarscape.trade_report_args(["--part1", "--on", "a", "--off", "b", "--nodisease", "c", "--iva3", "d", "--xl", "e"])
        @test p.mode == :part1 && p.label == "part1" && p.folders["nodisease"] == "c"
        c = Sugarscape.trade_report_args(["--confirm", "--vi1", "a", "--off", "b", "--label", "x"])
        @test c.mode == :confirm && c.label == "x"
        @test usage(["--confirm", "--vi1", "missing", "--off", "missing", "--out", dir]) == 2
        # a real screening
        args = ["--base", "today=trade-today-VI-1-s80-20-p500,trade-today-nodisease-VI-1-s80-20-p500,trade-today-IV-A3-s80-20-p300",
                "--arms", "A=trade-A-VI-1-s80-20-p500,trade-A-nodisease-VI-1-s80-20-p500,trade-today-IV-A3-s80-20-p300",
                "--off", "trade-today-off-VI-1-s80-20-p500", "--xl", joinpath("scorecard-xl-s80-20", "VI-1"), "--out", dir]
        code, printed = mktemp() do path, io
            code = redirect_stdout(() -> Sugarscape.trade_report_main(args), io)
            flush(io)
            return code, Base.read(path, String)
        end
        file = joinpath(dir, "trade-screen.md")
        @test code == 0 && isfile(file)
        written = Base.read(file, String)
        @test printed == written * "-> " * file * "\n"
        @test occursin("Chosen: A.", written) && !isfile(file * ".tmp")
        # an arm on other seeds is a usage error (its folder is made in "screening refuses an arm on other seeds")
        other = copy(args)
        other[4] = "A=trade-s81-VI-1-s81-20-p500,trade-A-nodisease-VI-1-s80-20-p500,trade-today-IV-A3-s80-20-p300"
        @test usage([other; ["--label", "other"]]) == 2
        @test !isfile(joinpath(dir, "trade-other.md"))
    end
end
