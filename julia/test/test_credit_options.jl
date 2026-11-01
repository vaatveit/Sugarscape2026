# The Julia-only credit study options (claims_outlive_lender, credit_reach, lender_limit); each is off by default.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function opt_model(; kw...)  # p.55's threshold unless a test sets another
    return tiny_model(
        ones(Int, 7, 7);
        sex=true,
        credit=(10, 10.0),
        merge((; fertility_threshold=1.0), values(kw))...,
    )
end

function opt_person(m, x, y, age, sugar; initial=60.0, finish=40, income=10.0)
    a = put_agent(m, x, y; sugar=sugar)
    a.sex, a.fertility_start, a.fertility_end = :F, 12, finish
    a.age, a.initial_sugar, a.last_income = age, initial, income
    return a
end

@testset "credit options: validation" begin
    base = (; sex=true, credit=(10, 10.0))
    @test_throws ArgumentError validate(Config(; sex=true, credit=nothing, claims_outlive_lender=true))
    @test_throws ArgumentError validate(Config(; sex=true, credit=nothing, lender_limit=true))
    @test_throws ArgumentError validate(Config(; sex=true, credit=nothing, credit_reach=2.0))
    @test_throws ArgumentError validate(Config(; base..., credit_reach=0.0))
    @test_throws ArgumentError validate(Config(; base..., claims_outlive_lender=true, inheritance=true))
    validate(Config(; base..., claims_outlive_lender=true, credit_reach=2.0, lender_limit=true))
end

@testset "credit_reach: the limit moves with it" begin
    # income 10 x d 10 = 100 of income; a loan's due is 2 x its principal, so 50 is the most at reach 1.
    m = opt_model(; credit_reach=1.0)
    old = opt_person(m, 3, 3, 50, 1000.0)
    atlimit = opt_person(m, 3, 4, 20, 10.0; initial=60.0)
    @test creditworthy(m, atlimit, 100.0) && !creditworthy(m, atlimit, 100.0001)
    m2 = opt_model(; credit_reach=2.0)
    opt_person(m2, 3, 3, 50, 1000.0)
    a2 = opt_person(m2, 3, 4, 20, 10.0; initial=60.0)
    @test creditworthy(m2, a2, 200.0) && !creditworthy(m2, a2, 200.0001)
end

@testset "claims_outlive_lender: the debt stands and the sugar leaves the world" begin
    m = opt_model(; claims_outlive_lender=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    Sugarscape.credit_on_death!(m, old, ())
    old.alive = false
    @test loan in m.loans && haskey(m.debts, young.id)
    before = old.sugar
    young.sugar = 200.0
    m.t = loan.due_t
    settle_loans!(m)
    @test young.sugar == 200.0 - loan.due
    @test old.sugar == before  # no agent received it
    @test isempty(m.loans) && !haskey(m.lent, old.id)
end

@testset "claims_outlive_lender: an unpaid debt rolls over, and a borrower's death still voids" begin
    m = opt_model(; claims_outlive_lender=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    Sugarscape.credit_on_death!(m, old, ())
    old.alive = false
    young.sugar = 10.0
    m.t = loan.due_t
    settle_loans!(m)
    @test young.sugar == 5.0 && length(m.loans) == 1 && m.loans[1].lender === old
    Sugarscape.credit_on_death!(m, young, ())
    @test isempty(m.loans) && isempty(m.lent)
end

@testset "claims_outlive_lender: both dying together voids" begin
    m = opt_model(; claims_outlive_lender=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    seek_credit!(m, young)
    Sugarscape.credit_on_deaths!(m, (old, young), (old, young))
    @test isempty(m.loans) && isempty(m.lent) && isempty(m.debts)
end

@testset "lender_limit: at most half its wealth in a period, in all" begin
    m = opt_model(; lender_limit=true)
    old = opt_person(m, 3, 3, 50, 100.0)  # past childbearing
    @test lending_left(m, old) == 50.0
    a = opt_person(m, 3, 4, 20, 40.0)  # lacks 20
    b = opt_person(m, 4, 3, 20, 20.0)  # lacks 40, gets the 30 left
    c = opt_person(m, 2, 3, 20, 20.0)
    seek_credit!(m, a)
    seek_credit!(m, b)
    @test isempty(seek_credit!(m, c))
    @test old.sugar == 50.0
    empty!(m.lend_left)  # as step! does at a period's start
    @test lending_left(m, old) == 25.0
    @test length(seek_credit!(m, c)) == 1 && old.sugar == 25.0
end

@testset "lender_limit: a childbearing lender keeps what children need" begin
    m = opt_model(; lender_limit=true)
    rich = opt_person(m, 3, 3, 20, 100.0)  # needs 60, so 40 by the rule, 50 by the limit
    poor = opt_person(m, 3, 4, 20, 0.0)
    @test seek_credit!(m, poor)[1].principal == 40.0
end

@testset "lender_limit: step! clears the budgets and settling draws on none" begin
    m = opt_model(; lender_limit=true)
    old = opt_person(m, 3, 3, 50, 100.0)
    young = opt_person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    @test haskey(m.lend_left, old.id)
    left = m.lend_left[old.id]
    young.sugar = 0.0
    m.t = loan.due_t
    settle_loans!(m)  # a rollover
    @test m.lend_left[old.id] == left
    step!(m)
    @test !haskey(m.lend_left, old.id) || m.lend_left[old.id] != left
end

@testset "off: lending_left doesn't limit" begin
    m = opt_model()
    @test lending_left(m, opt_person(m, 3, 3, 50, 100.0)) == Inf
end
