# xxl: the loan tracer (docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md, "A loan tracer"). Hand-built
# worlds pin each table; short VI-1 runs show the trace leaves the run alone and counts what the scorecard counts.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: LoanTrace, tally, window_index, age_band, trace_start!, trace_period!, trace_finish!
using Sugarscape: TRACE_SAMPLE_COLUMNS, death_cause, Loan, add_loan!, with_steps

const LT_REG = load_registry()

# A hand-made loan, started on the model's trace as seek_credit! would.
function lt_loan!(m, lender, borrower, principal, due, due_t)
    loan = add_loan!(m, Loan(lender, borrower, principal, due, due_t))
    trace_start!(m.loan_trace, m, loan)
    return loan
end

# One period: step!, then the trace's end of period.
function lt_step!(m, n=1)
    for _ in 1:n
        step!(m)
        trace_period!(m.loan_trace, m)
    end
    return m
end

# A bare world with a trace of loans of this term.
function lt_model(; term=5, sample_every=100, kw...)
    m = tiny_model(zeros(Int, 9, 9); sex=true, credit=(term, 0.0), kw...)
    m.loan_trace = LoanTrace(term; sample_every=sample_every)
    return m
end

# A lender with sugar to spare that burns none, and a borrower that burns 1 a period.
function lt_pair(m; lender_max_age=Inf, borrower_sugar=50.0)
    lender = put_agent(m, 1, 1; sugar=100.0, metabolism=0, max_age=lender_max_age)
    borrower = put_agent(m, 6, 6; sugar=borrower_sugar)
    return lender, borrower
end

# A lender past childbearing age at (1, 1), and next to it a borrower of childbearing age short of sugar, on the one
# site with sugar: in the next step! seek_credit! lends 16.
function lt_lending_pair(; lender_max_age=Inf)
    capacity = zeros(Int, 9, 9)
    capacity[2 + 1, 1 + 1] = 10
    m = tiny_model(capacity; sex=true, credit=(5, 0.0))
    m.loan_trace = LoanTrace(5)
    lender = put_agent(m, 1, 1; sugar=100.0, max_age=lender_max_age)
    lender.sex, lender.fertility_start, lender.fertility_end = :F, 12, 40
    lender.initial_sugar, lender.age = 10.0, 50
    b = put_agent(m, 2, 1; sugar=5.0)
    b.sex, b.fertility_start, b.fertility_end, b.initial_sugar = :M, 12, 50, 30.0
    b.age = 20
    return m, lender, b
end

@testset "loan trace: a window and a band" begin
    @test [window_index(t) for t in (1, 100, 101, 500, 501)] == [1, 1, 2, 2, 3]
    @test [age_band(a) for a in (0, 4.9, 5, 99, 100, 120)] == ["0", "0", "5", "95", "95", "95"]
    @test LoanTrace(10).census_every == 50 && LoanTrace(10).sample_every == 100
end

@testset "loan trace: death_cause" begin
    m = tiny_model(zeros(Int, 9, 9); spice=true)
    a = put_agent(m, 1, 1; sugar=-1.0, max_age=1)
    a.age, a.spice = 1, 5.0
    @test death_cause(m, a) === :old_age
    a.age = 0
    @test death_cause(m, a) === :sugar
    a.sugar = 3.0
    a.spice = 0.0
    @test death_cause(m, a) === :spice
    push!(m.killed, a.id)
    @test death_cause(m, a) === :killed
end

@testset "loan trace: repaid" begin
    m = lt_model(; term=2)
    lender, borrower = lt_pair(m)
    lt_loan!(m, lender, borrower, 5.0, 5.0, 2)
    tr = m.loan_trace
    @test tally(tr, 1, "started") == 1 && length(tr.chains) == 1
    lt_step!(m, 3)  # due at the end of the third period
    @test tally(tr, 1, "ended", "repaid") == 1
    @test tally(tr, 1, "received", "repaid") == 5.0
    @test tally(tr, 1, "principal", "repaid") == 5.0
    @test tally(tr, 1, "void_elapsed", "repaid", "2") == 1
    @test tally(tr, 1, "doomed", "neither", "repaid") == 1
    @test isempty(tr.chains) && isempty(tr.voids)
    @test tally(tr, 2, "ended", "repaid") == 0 && tally(tr, 1, "ended", "voided_lender") == 0
end

@testset "loan trace: a lender dies" begin
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m; lender_max_age=53)
    lender.age = 52
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    tr = m.loan_trace
    step!(m)
    @test !lender.alive && length(tr.voids) == 1  # resolved at the period's end
    trace_period!(tr, m)
    @test isempty(tr.voids) && isempty(tr.chains)
    @test tally(tr, 1, "ended", "voided_lender") == 1
    @test tally(tr, 1, "received", "voided_lender") == 0
    @test tally(tr, 1, "void_cause", "lender", "old_age") == 1
    @test tally(tr, 1, "void_age", "lender", "50") == 1
    @test tally(tr, 1, "void_elapsed", "voided_lender", "0") == 1  # made in period 1, voided in period 1
    @test tally(tr, 1, "void_cause", "borrower", "sugar") == 0
end

@testset "loan trace: a borrower starves" begin
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m)
    borrower.metabolism, borrower.sugar = 5, 3.0
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    lt_step!(m)
    tr = m.loan_trace
    @test !borrower.alive && lender.alive
    @test tally(tr, 1, "void_cause", "borrower", "sugar") == 1
    @test tally(tr, 1, "ended", "voided_borrower") == 1
    @test tally(tr, 1, "void_cause", "lender", "old_age") == 0

    # Sugar kept, spice run out.
    m = lt_model(; term=5, spice=true)
    lender, borrower = lt_pair(m)
    lender.spice = 100.0
    borrower.spice, borrower.spice_metabolism = 2.0, 5
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    lt_step!(m)
    tr = m.loan_trace
    @test !borrower.alive && borrower.sugar > 0
    @test tally(tr, 1, "void_cause", "borrower", "spice") == 1
    @test tally(tr, 1, "ended", "voided_borrower") == 1
end

@testset "loan trace: both die in one period" begin
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m; lender_max_age=1)
    borrower.metabolism, borrower.sugar = 5, 3.0  # starves in the sweep; the lender reaches its max age after
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    lt_step!(m)
    tr = m.loan_trace
    @test !borrower.alive && !lender.alive
    @test tally(tr, 1, "ended", "voided_both") == 1
    @test tally(tr, 1, "ended", "voided_lender") == 0 && tally(tr, 1, "ended", "voided_borrower") == 0
    @test tally(tr, 1, "void_cause", "borrower", "sugar") == 1
    @test tally(tr, 1, "void_cause", "lender", "old_age") == 1
    @test tally(tr, 1, "void_age", "borrower", "0") == 1 && tally(tr, 1, "void_age", "lender", "0") == 1
end

@testset "loan trace: two loans from one lender" begin
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m; lender_max_age=1)
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    lt_loan!(m, lender, borrower, 3.0, 3.0, 5)
    lt_step!(m)
    tr = m.loan_trace
    @test tally(tr, 1, "started") == 2
    @test tally(tr, 1, "ended", "voided_lender") == 2
    @test tally(tr, 1, "void_cause", "lender", "old_age") == 2
    @test tally(tr, 1, "principal", "voided_lender") == 8.0
    @test isempty(tr.chains)
end

@testset "loan trace: made and voided in one period" begin
    m, lender, b = lt_lending_pair(; lender_max_age=51)  # 50 + 1 at the period's end
    lt_step!(m)
    tr = m.loan_trace
    @test !lender.alive && b.alive && m.loans_made == 1
    @test tally(tr, 1, "started") == 1
    @test tally(tr, 1, "ended", "voided_lender") == 1
    @test tally(tr, 1, "void_elapsed", "voided_lender", "0") == 1
    @test tally(tr, 1, "party_kind", "lender", "past_fertile") == 1
    @test tally(tr, 1, "party_kind", "borrower", "fertile") == 1
    @test tally(tr, 1, "party_sex", "lender", "F") == 1 && tally(tr, 1, "party_sex", "borrower", "M") == 1
    @test tally(tr, 1, "started_bands", "50", "20") == 1
    @test isempty(tr.chains)
end

@testset "loan trace: rollovers" begin
    m = lt_model(; term=2)
    lender, borrower = lt_pair(m; borrower_sugar=20.0)
    lt_loan!(m, lender, borrower, 40.0, 40.0, 0)  # due at the end of the first period
    tr = m.loan_trace
    lt_step!(m, 3)  # pays 9.5 and rolls 30.5; pays 3.75 and rolls 26.75
    @test tally(tr, 1, "rolled") == 2 && length(tr.chains) == 1 && tally(tr, 1, "ended", "repaid") == 0
    borrower.sugar += 100.0
    lt_step!(m, 2)
    @test tally(tr, 1, "started") == 1 && tally(tr, 1, "rolled") == 2
    @test tally(tr, 1, "ended", "repaid") == 1
    @test tally(tr, 1, "principal", "repaid") == 40.0
    @test tally(tr, 1, "void_elapsed", "repaid", "4") == 1  # begun in period 1, repaid in period 5
    received = tally(tr, 1, "received", "repaid")
    @test received ≈ 9.5 + 3.75 + 26.75
    @test lender.sugar - 100.0 ≈ received
    @test isempty(tr.chains)
end

@testset "loan trace: rolls over, then dies" begin
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m)
    borrower.metabolism, borrower.sugar = 4, 10.0
    lt_loan!(m, lender, borrower, 50.0, 50.0, 0)
    lt_step!(m)  # 10 - 4 = 6 < 50: pays 3, the rest rolls
    tr = m.loan_trace
    @test tally(tr, 1, "rolled") == 1 && length(tr.chains) == 1
    lt_step!(m)  # 3 - 4 < 0: the borrower starves
    @test !borrower.alive
    @test tally(tr, 1, "ended", "voided_borrower") == 1
    @test tally(tr, 1, "received", "voided_borrower") == 3.0
    @test tally(tr, 1, "ended", "repaid") == 0
    @test lender.sugar == 103.0
end

@testset "loan trace: doomed at the start" begin
    for (max_age, doomed, outcome) in ((10, "lender", "voided_lender"), (11, "neither", "repaid"))
        m = lt_model(; term=5)
        lender, borrower = lt_pair(m; lender_max_age=max_age)
        lender.age = 4
        lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
        lt_step!(m, 6)  # settled at the end of the sixth; the lender is 10 by then
        tr = m.loan_trace
        @test tally(tr, 1, "doomed", doomed, outcome) == 1
        @test tally(tr, 1, "ended", outcome) == 1
    end
    # Each side's class, whatever came of the loan.
    for (lender_max, borrower_max, doomed) in
        ((10, Inf, "lender"), (Inf, 10, "borrower"), (10, 10, "both"), (11, 11, "neither"))
        m = lt_model(; term=5)
        lender, borrower = lt_pair(m; lender_max_age=lender_max)
        lender.age = borrower.age = 4
        borrower.max_age = Float64(borrower_max)
        lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
        lt_step!(m, 6)
        tr = m.loan_trace
        outcomes = ("repaid", "voided_lender", "voided_borrower", "voided_both")
        @test sum(tally(tr, 1, "doomed", doomed, o) for o in outcomes) == 1
        classes = ("neither", "lender", "borrower", "both")
        @test sum(tally(tr, 1, "doomed", k, o) for k in classes for o in outcomes) == 1
    end
end

@testset "loan trace: inheritance" begin
    m = lt_model(; term=5, inheritance=true)
    lender, borrower = lt_pair(m; lender_max_age=1)
    c1 = put_agent(m, 3, 3; sugar=10.0, metabolism=0)
    c2 = put_agent(m, 7, 7; sugar=10.0, metabolism=0)
    push!(lender.children, c1, c2)
    lt_loan!(m, lender, borrower, 10.0, 10.0, 5)
    tr = m.loan_trace
    lt_step!(m)
    @test !lender.alive && length(m.loans) == 2 && length(tr.chains) == 2
    @test all(c.weight == 0.5 for c in values(tr.chains))
    @test all(loan.lender in (c1, c2) for loan in keys(tr.chains))
    @test tally(tr, 1, "ended", "voided_lender") == 0
    lt_step!(m, 5)
    @test isempty(tr.chains) && isempty(m.loans)
    @test tally(tr, 1, "started") == 1
    @test tally(tr, 1, "ended", "repaid") ≈ 1
    @test tally(tr, 1, "received", "repaid") ≈ 10.0
    @test tally(tr, 1, "principal", "repaid") ≈ 10.0
    @test tally(tr, 1, "ended", "voided_lender") == 0
    @test tally(tr, 1, "void_elapsed", "repaid", "5") ≈ 1
end

@testset "loan trace: a child during the chain" begin
    for (child, expected) in ((true, "yes"), (false, "no"))
        m = lt_model(; term=2)
        lender, borrower = lt_pair(m)
        lt_loan!(m, lender, borrower, 5.0, 5.0, 2)
        child && push!(borrower.children, put_agent(m, 4, 4))
        lt_step!(m, 3)
        @test tally(m.loan_trace, 1, "child", "repaid", expected) == 1
        @test tally(m.loan_trace, 1, "child", "repaid", expected == "yes" ? "no" : "yes") == 0
    end
    # A child before the loan doesn't count; a child and then death does.
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m)
    push!(borrower.children, put_agent(m, 4, 4))
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    lt_step!(m)
    @test tally(m.loan_trace, 1, "child", "repaid", "no") == 0 && length(m.loan_trace.chains) == 1
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m)
    borrower.metabolism, borrower.sugar = 5, 3.0
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    push!(borrower.children, put_agent(m, 4, 4))
    lt_step!(m)
    @test !borrower.alive
    @test tally(m.loan_trace, 1, "child", "voided_borrower", "yes") == 1
    # A dead lender's loan: the borrower is alive and its children are read as they stand.
    m = lt_model(; term=5)
    lender, borrower = lt_pair(m; lender_max_age=1)
    lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    push!(borrower.children, put_agent(m, 4, 4))
    lt_step!(m)
    @test tally(m.loan_trace, 1, "child", "voided_lender", "yes") == 1
end

@testset "loan trace: a sampled chain" begin
    m = lt_model(; term=2, sample_every=1)
    lender = put_agent(m, 1, 1; sugar=100.0, metabolism=0, max_age=80)
    lender.age = 30
    borrower = put_agent(m, 6, 6; sugar=50.0)
    borrower.last_income = 3.0
    lt_loan!(m, lender, borrower, 5.0, 5.0, 2)
    lt_step!(m, 3)
    tr = m.loan_trace
    @test length(tr.sampled) == 1 && length(TRACE_SAMPLE_COLUMNS) == 22
    @test all(length(r) == 22 for r in tr.sampled)
    row = Dict(zip(TRACE_SAMPLE_COLUMNS, tr.sampled[1]))
    @test row["chain"] == 1 && row["t_start"] == 1 && row["t_end"] == 3
    @test row["outcome"] == "repaid" && row["rollovers"] == 0 && row["weight"] == 1.0
    @test (row["lender_id"], row["lender_age"], row["lender_max_age"], row["lender_sex"], row["lender_sugar"]) ==
        (lender.id, 30, 80.0, "none", 100.0)
    @test row["borrower_id"] == borrower.id && row["borrower_age"] == 0 && row["borrower_max_age"] == Inf
    @test row["borrower_sex"] == "none" && row["borrower_sugar"] == 50.0 && row["borrower_income"] == 3.0
    @test (row["principal"], row["due"], row["received"]) == (5.0, 5.0, 5.0)
    @test row["child"] == "no" && row["doomed"] == "neither"

    # Every sample_every-th chain, those unfinished at the finish too: an empty t_end.
    m = lt_model(; term=5, sample_every=2)
    lender, borrower = lt_pair(m)
    for _ in 1:3
        lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    end
    lt_step!(m)
    tr = m.loan_trace
    @test isempty(tr.sampled)
    trace_finish!(tr, m)
    @test tally(tr, 1, "unfinished") == 3 && isempty(tr.chains)
    @test length(tr.sampled) == 1
    row = Dict(zip(TRACE_SAMPLE_COLUMNS, tr.sampled[1]))
    @test row["chain"] == 2 && row["outcome"] == "unfinished" && row["t_end"] == ""

    m = lt_model(; term=5)  # sample_every = 100
    lender, borrower = lt_pair(m)
    for _ in 1:3
        lt_loan!(m, lender, borrower, 5.0, 5.0, 5)
    end
    lt_step!(m, 6)
    trace_finish!(m.loan_trace, m)
    @test isempty(m.loan_trace.sampled) && tally(m.loan_trace, 1, "ended", "repaid") == 3
end

@testset "loan trace: the run is the same" begin
    vi1 = with_steps(find_experiment(LT_REG, "VI-1"), 30)
    plain, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_DEFAULTS)
    tr = LoanTrace(10)
    traced, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_DEFAULTS, loan_trace=tr)
    @test isequal(plain, traced)
    @test tally(tr, 1, "started") > 0
end

@testset "loan trace: the counts are the scorecard's" begin
    vi1 = with_steps(find_experiment(LT_REG, "VI-1"), 120)
    tr = LoanTrace(10)
    rows, _ = Sugarscape.timed_seed(vi1, 0; xxl=XXL_DEFAULTS, scorecard=true, loan_trace=tr)
    cols = ["t"; metric_columns(to_xxl(vi1.config, XXL_DEFAULTS); scorecard=true)]
    voids = ("voided_lender", "voided_borrower", "voided_both")
    total_voided = 0.0
    for w in 1:3
        sel = [r for r in rows if r[1] >= 1 && window_index(Int(r[1])) == w]
        col(name) = sum(r[findfirst(==(name), cols)] for r in sel; init=0.0)
        @test col("loans_started") == tally(tr, w, "started")
        @test col("loans_repaid") == tally(tr, w, "ended", "repaid")
        @test col("loans_voided") == sum(tally(tr, w, "ended", o) for o in voids)
        @test col("loans_rolled") == tally(tr, w, "rolled")
        total_voided += col("loans_voided")
    end
    @test total_voided > 0
    ended = sum(tally(tr, w, "ended", o) for w in 1:3 for o in ("repaid", voids...))
    unfinished = sum(tally(tr, w, "unfinished") for w in 1:3)
    @test sum(tally(tr, w, "started") for w in 1:3) == ended + unfinished
    @test unfinished > 0 && isempty(tr.chains) && isempty(tr.voids)
end

@testset "loan trace: not with a checkpoint" begin
    tiny = find_experiment(LT_REG, "TEST-tiny")
    checkpoint = (; restore=() -> nothing, period_done=(m, rows, clock) -> false)
    @test_throws ArgumentError Sugarscape.timed_seed(
        tiny, 0; xxl=XXL_V1, loan_trace=LoanTrace(10), checkpoint=checkpoint
    )
end

@testset "loan trace: seed_job passes loan_trace only when it is set" begin
    tiny = find_experiment(LT_REG, "TEST-tiny")
    stand_in(exp, k; xl=false, xxl=nothing) = ([[0.0]], (; seed=k))
    @test Sugarscape.seed_job(tiny, 0, false, stand_in; xxl=XXL_BOOK)[1] == [[0.0]]
    with_trace(exp, k; xl=false, xxl=nothing, scorecard=false, loan_trace=nothing) =
        ([[loan_trace === nothing ? 0.0 : 1.0]], (; seed=k))
    @test Sugarscape.seed_job(tiny, 0, false, with_trace; xxl=XXL_BOOK, loan_trace=LoanTrace(10))[1] == [[1.0]]
end
