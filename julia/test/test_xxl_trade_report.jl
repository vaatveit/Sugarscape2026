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
"""
function tr_agents(r)
    ends = [10.0, 10.0, 10.0, 10.0, 10r, 10r]
    return permutedims(hcat((Float64[i, 2, 2, 3, 20, 10, 10, ends[i], 0, i - 1, 0] for i in 1:6)...))
end

"""
A study folder of `n` seeds under `dir/name` (first seed from the name's `-s<k>-`), shaped like `run_trade_arm`'s: a
fingerprint with `xxl` (the rules line, `settings` added at its end), `extra` (such as `trade: off`), the periods and the
readings' window, and per seed its CSV, its trade readings and its agent snapshot. Every keyword is a number held
throughout, or a function of the seed's place (1, 2, ...) giving one; `pop` may also give a whole population (t = 0 to
`periods`). The population is 2,000 at t = 0, `low` (else `pop`) at t = 1 and `pop` after. The trade readings hold the
same row every period, the pairs and gaps only at every tenth. `agents` gives a seed's snapshot, else `tr_agents(ratio)`.
"""
function tr_folder(dir, name; n=20, periods=500, xxl=TR_XXL, settings="", extra="", pop=1000.0, low=nothing,
                   sick=0.08, diseases=3.0, gini=0.3, sugar=40.0, spice=30.0, trades=1000.0, price=1.0, price_sd=0.2,
                   moved=1.5, healthy=900.0, sick_n=80.0, hh=600.0, hs=300.0, ss=100.0, hh10=0.3,
                   pairs=(800.0, 150.0, 50.0), gaps=(0.1, 0.4), ratio=1.2, agents=nothing)
    folder = joinpath(dir, name)
    mkpath(folder)
    write(joinpath(folder, "fingerprint.txt"),
          "julia\n$xxl$(isempty(settings) ? "" : " " * settings)\nlook: centred\n({G1}, {M, S, K, T, L10,10, E})\n" *
          "steps=500\n$TR_CONFIG\nxl map sha256=xl-a\n" * (isempty(extra) ? "" : extra * "\n") *
          "code sha256=code-a\nperiods=$periods\ntrade readings: window=($(max(1, periods - 99)), $periods)\n")
    first_seed = parse(Int, match(r"-s(\d+)-", name).captures[1])
    each(x, i) = x isa Function ? x(i) : x
    column(x) = fill(Float64(x), periods + 1)
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
        rows = map(1:periods) do t
            tenth = t % 10 == 0
            return Float64[t, each(healthy, i), 20, each(sick_n, i), h + s + x, h, s, x, 10, 70, each(hh10, i), 1.0,
                           (tenth ? y : (NaN, NaN, NaN))..., (tenth ? z : (NaN, NaN))...]
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

# The last cell of the reading table's row `row` of arm `arm`: pass, near or fail.
function tr_result(report, arm, row)
    line = findfirst(l -> startswith(l, "| $arm | $row |"), split(report, "\n"))
    line === nothing && return "missing"
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
        e = Sugarscape.matched_ratio(zeros(0, 11), 1.0)
        @test isnan(e.ratio) && e.kept == 0 && e.dropped == 0
    end

    @testset "each bar at its edge" begin
        arms = [
            arm("r110"; ratio=1.1), arm("r109"; ratio=1.09), arm("r100"; ratio=1.0),
            arm("hh25"; hh10=0.25), arm("hh24"; hh10=0.24), arm("hh20"; hh10=0.2),
            arm("nd2"), arm("nd195"; nodisease=study("nd195", nod("nd195"; trades=950.0))),
            arm("nd18"; nodisease=study("nd18", nod("nd18"; trades=900.0))),
            arm("sick50"; hs=150.0, ss=50.0), arm("sick48"; hs=140.0, ss=50.0), arm("sick40"; hs=100.0, ss=50.0),
            arm("tr95"; low=950.0), arm("trnear"; low=i -> i == 1 ? 890.0 : 1000.0), arm("trfail"; low=900.0 * 0.95),
            arm("x9at18"; diseases=i -> i <= 18 ? 3.0 : 0.0), arm("x9at17"; diseases=i -> i <= 17 ? 3.0 : 0.0),
            arm("x10at18"; sick=i -> i <= 18 ? 0.08 : 0.3), arm("x10at17"; sick=i -> i <= 17 ? 0.08 : 0.3),
            arm("x6at15"; price_sd=0.3), arm("x6near"; price_sd=0.31), arm("x6fail"; price_sd=0.4),
        ]
        r = screen(arms)
        @test tr_result(r, "r110", "Richer with trade") == "pass"
        @test tr_result(r, "r109", "Richer with trade") == "near"
        @test tr_result(r, "r100", "Richer with trade") == "fail"
        @test tr_result(r, "hh25", "Healthy trade") == "pass"
        @test tr_result(r, "hh24", "Healthy trade") == "near"
        @test tr_result(r, "hh20", "Healthy trade") == "fail"
        @test tr_result(r, "nd2", "Without disease") == "pass"
        @test tr_result(r, "nd195", "Without disease") == "near"
        @test tr_result(r, "nd18", "Without disease") == "fail"
        @test tr_result(r, "sick50", "Sick agents still trade") == "pass"
        @test tr_result(r, "sick48", "Sick agents still trade") == "near"
        @test tr_result(r, "sick40", "Sick agents still trade") == "fail"
        @test tr_result(r, "tr95", "Trough") == "pass"
        @test tr_result(r, "trnear", "Trough") == "near"  # the mean is far enough, one seed below
        @test tr_result(r, "trfail", "Trough") == "fail"  # every seed below 90% of today's lowest
        @test tr_result(r, "x9at18", "Disease: X9") == "pass"
        @test tr_result(r, "x9at17", "Disease: X9") == "near"
        @test tr_result(r, "x10at18", "Disease: X10 per seed") == "pass"
        @test tr_result(r, "x10at17", "Disease: X10 per seed") == "near"
        @test tr_result(r, "x6at15", "Prices: X6") == "pass"
        @test tr_result(r, "x6near", "Prices: X6") == "near"
        @test tr_result(r, "x6fail", "Prices: X6") == "fail"
        @test tr_result(r, "r110", "Extinction") == "pass"
        # every arm has every row, and only the two arms made to fail the trough fail it
        for a in arms, row in ("Richer with trade", "Healthy trade", "Without disease", "Sick agents still trade",
                               "Trough", "Disease: X9", "Disease: X10 per seed", "Prices: X6", "Extinction")
            res = tr_result(r, a.name, row)
            @test res != "missing"
        end
        @test count(a -> tr_result(r, a.name, "Trough") == "pass", arms) == length(arms) - 2
        # with arms passing, one is chosen and no near arm is offered
        @test occursin("Chosen: ", r) && !occursin("Near passing", r)
    end

    @testset "the bars as printed" begin
        r = screen([arm("A")])
        @test occursin("at least 1.10, its 95% interval above 1", r)
        @test occursin("at least 25% of healthy agents", r)
        @test occursin("at least ×2 today's", r) && occursin("at least ×0.5 today's", r)
        @test occursin("mean at least 95% of today's", r) && occursin("none below 90% of today's lowest", r)
        @test occursin("at most 1.5", r) && occursin("at least 18 of 20", r)
        # the text comes from the constants
        @test occursin("at least $(Sugarscape.two_places(Sugarscape.RICHER_BAR)),", r)
        @test occursin("$(round(Int, 100 * Sugarscape.HEALTHY_TRADE_BAR))%", r)
        # the sick agents' reading names its bias
        @test occursin("died later in the same period", r)
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

        part1(name; kw...) = Sugarscape.trade_report(; label="p", part1=true, off, xl,
            base=Sugarscape.TradeArm("today", study(name, vi1(name; kw...)), base_nod, base_iva3))
        wrong = part1("p1wrong")  # ratio 1.2, 30% with a healthy partner
        @test occursin("The premise is wrong. Stop and report", wrong)
        holds = part1("p1holds"; ratio=1.0, hh10=0.1, hh=300.0, hs=900.0)  # 900 / (900 + 600) with a sick partner
        @test occursin("The diagnosis holds. Go on to Part 2", holds)
        @test occursin("| Healthy agents' exchanges with a sick partner | 0.6 |", holds)
        # recovering agents are a group of their own: 20 of 1,000 agents, 10 exchanges with one among them
        @test occursin("| Recovering agents: share of agents / exchanges with one per recovering agent | 0.02 / 0.5 |", holds)
        half = part1("p1half"; ratio=1.0, hh10=0.1, hh=300.0, hs=900.0, gaps=(0.3, 0.4))
        @test occursin("only half right: something besides movement", half)
        # Part 1 says which bars today already meets
        @test occursin("Today already meets the Richer with trade bar", wrong)
        @test !occursin("Today already meets", holds)
        @test occursin("## Trade on ÷ off", wrong) && occursin("## Traders against similar non-traders", wrong)
    end

    @testset "an extinct seed" begin
        gone = arm("gone"; pop=i -> i == 1 ? vcat(fill(1000.0, 200), zeros(301)) : 1000.0,
                   agents=i -> i == 1 ? zeros(0, 11) : tr_agents(1.2))
        m = Sugarscape.matched_over_seeds(gone.vi1)
        @test m.left_out == ["seed 80 went extinct at t = 200"] && length(m.per_seed) == 19 && m.kept == 19 * 6
        @test m.ratio ≈ 1.2
        r = screen([gone])
        @test occursin("**Seed 80 of gone, VI-1 went extinct at t = 200", r)
        @test tr_result(r, "gone", "Extinction") == "fail" && tr_result(r, "gone", "Richer with trade") == "pass"
        @test !occursin("NaN", r)
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
        @test occursin("| today | Healthy agents' mean resources at t = 500 | 1.067 |", r)
        @test occursin("| today | Population | 1 |", r)
        @test !occursin("has trade on", r)
        on_off = Sugarscape.trade_report(; label="t", base, arms=[arm("A")], off=base.vi1, xl)
        @test occursin("**The trade-off folder trade-today-VI-1-s80-20-p500 has trade on", on_off) && occursin("has trade on", on_off)
    end

    @testset "confirmation" begin
        confirm(ratio) = Sugarscape.trade_report(; label="c", confirm=true, off,
            base=Sugarscape.TradeArm("A", study("c$ratio", vi1("c$ratio"; ratio)), nothing, nothing))
        yes, no = confirm(1.2), confirm(1.0)
        @test tr_result(yes, "A", "Richer with trade") == "pass" && occursin("The ratio passes again", yes)
        @test tr_result(no, "A", "Richer with trade") == "fail" && occursin("not confirmed", no)
        @test occursin("## Trade on ÷ off", yes)
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
    end
end
