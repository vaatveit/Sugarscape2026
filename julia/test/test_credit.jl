# Ports tests/test_credit.py.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function credit_model(; kw...)  # p.55's threshold unless a test sets another
    return tiny_model(
        ones(Int, 7, 7);
        sex=true,
        credit=(10, 10.0),
        merge((; fertility_threshold=1.0), values(kw))...,
    )
end

function person(m, x, y, age, sugar; initial=60.0, finish=40, income=10.0)
    a = put_agent(m, x, y; sugar=sugar)
    a.sex, a.fertility_start, a.fertility_end = :F, 12, finish
    a.age, a.initial_sugar, a.last_income = age, initial, income
    return a
end

@testset "test_old_agent_lends_half_its_wealth" begin  # p.132
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    @test available_to_lend(m, old) == 50.0 && shortfall(m, young) == 40.0
    loans = seek_credit!(m, young)
    @test length(loans) == 1 && loans[1].principal == 40.0  # shortfall 40 <= 50 available
    @test young.sugar == 60.0 && old.sugar == 60.0 && loans[1].due ≈ 80.0
    @test loans[1].due_t == m.t + 10 && m.loans == loans
end

@testset "test_fertile_lender_lends_only_surplus" begin
    m = credit_model()
    person(m, 3, 3, 20, 70.0)
    poor = person(m, 3, 4, 20, 20.0)
    @test seek_credit!(m, poor)[1].principal == 10.0
end

@testset "test_children_and_the_comfortable_neither_borrow_nor_lend" begin
    m = credit_model()
    child = person(m, 3, 3, 5, 100.0)
    ok = person(m, 3, 4, 20, 60.0)
    @test available_to_lend(m, child) == 0.0 && shortfall(m, child) == 0.0
    @test available_to_lend(m, ok) == 0.0 && shortfall(m, ok) == 0.0
end

@testset "test_not_creditworthy_without_income" begin
    m = credit_model()
    person(m, 3, 3, 50, 100.0)
    poor = person(m, 3, 4, 20, 20.0; income=1.0)
    @test isempty(seek_credit!(m, poor))  # income 1 x d 10 < 80 due
end

@testset "test_settlement_pays_or_renegotiates" begin  # p.133
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    m.t = loan.due_t
    young.sugar = 50.0
    settle_loans!(m)
    @test young.sugar == 25.0 && old.sugar == 60.0 + 25.0
    @test length(m.loans) == 1
    new = m.loans[1]
    @test new.principal ≈ 80.0 - 25.0 && new.due_t == m.t + 10 && new.lender === old
end

@testset "test_settlement_repays_in_full" begin
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    loan = seek_credit!(m, young)[1]
    m.t = loan.due_t
    young.sugar = 100.0
    settle_loans!(m)
    @test young.sugar == 20.0 && old.sugar == 140.0 && isempty(m.loans)
end

@testset "test_deaths_void_or_pass_loans" begin
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    seek_credit!(m, young)
    die!(m, young)
    @test isempty(m.loans) && old.sugar == 60.0
    m.t = 10
    settle_loans!(m)
    @test old.sugar == 60.0
    m2 = credit_model(; inheritance=true)
    lender = person(m2, 3, 3, 50, 100.0)
    kid = person(m2, 0, 0, 20, 80.0)
    push!(lender.children, kid)
    borrower = person(m2, 3, 4, 20, 20.0)
    seek_credit!(m2, borrower)
    die!(m2, lender)
    @test [l.lender for l in m2.loans] == [kid]
    m3 = credit_model()
    lender3 = person(m3, 3, 3, 50, 100.0)
    seek_credit!(m3, person(m3, 3, 4, 20, 20.0))
    die!(m3, lender3)
    @test isempty(m3.loans)  # no inheritance: the borrower keeps the loan
end

@testset "test_credit_runs_in_the_model" begin
    m = Model(
        Config(;
            sex=true, credit=(10, 10.0), max_age=(60, 100), endowment=(50, 100), seed=2
        ),
    )
    ok = true
    for _ in 1:120
        step!(m)
        ok &= all(l.lender.alive && l.borrower.alive for l in m.loans)
    end
    @test ok && !isempty(m.loans)
end

@testset "test_debt_owed_to_a_dead_parent_is_extinguished_not_self_lent" begin
    m = credit_model(; inheritance=true)
    lender = person(m, 3, 3, 50, 100.0)
    kid = person(m, 3, 4, 20, 20.0)
    push!(lender.children, kid)
    seek_credit!(m, kid)
    die!(m, lender)
    @test isempty(m.loans)
end

@testset "test_spice_landscape_loans_move_sugar_only" begin
    m = credit_model(; spice=true)
    old, young = person(m, 3, 3, 50, 100.0), person(m, 3, 4, 20, 20.0)
    for a in (old, young)
        a.spice = a.initial_spice = 30.0
    end
    loan = seek_credit!(m, young)[1]
    @test loan.principal == 40.0 && young.sugar == 60.0 && old.sugar == 60.0
    @test old.spice == young.spice == 30.0
end

@testset "test_all_rules_society_runs" begin  # Animation VI-1 rule set
    cfg = Config(;
        spice=true,
        trade=true,
        sex=true,
        metabolism=(1, 5),
        spice_metabolism=(1, 5),
        vision=(1, 5),
        endowment=(25, 50),
        initial_population=200,
        max_age=(60, 100),
        tag_length=11,
        culture=true,
        credit=(10, 10.0),
        disease_list=25,
        diseases_per_agent=10,
        seed=3,
    )
    m = Model(cfg)
    ok = true
    for _ in 1:40
        step!(m)
        ok &= all(agent_at(m, a.x, a.y) === a for a in m.agents)
        ok &= all(loan.lender.alive && loan.borrower.alive for loan in m.loans)
    end
    @test ok
end

@testset "test_credit_follows_the_variant_fertility_threshold" begin
    m = credit_model(; fertility_threshold=0.5)
    rich = person(m, 3, 3, 20, 70.0)
    poor = person(m, 3, 4, 20, 20.0)  # endowed with 60: fertile at 30
    @test shortfall(m, poor) == 10.0 && available_to_lend(m, rich) == 40.0
end

@testset "creditworthiness counts the borrower's other loans" begin
    m = credit_model()
    person(m, 3, 3, 50, 1000.0)
    poor = person(m, 3, 4, 20, 20.0; income=10.0)
    @test length(seek_credit!(m, poor)) == 1  # owes 80 now: 10 x 10 - 80 = 20 left
    poor.sugar = 20.0
    @test isempty(seek_credit!(m, poor))  # another 40 (due 80) exceeds what income covers
end

@testset "the loan indexes match the loan book" begin
    # creditworthy sums a borrower's loans from m.debts; they must be the loan book's, in its order, so the sum
    # (and every run) is unchanged.
    cfg = replace_config(find_experiment(load_registry(), "VI-1").config; seed=2)
    m = Model(cfg)
    ok, seen = true, 0
    for _ in 1:150
        step!(m)
        for (id, list) in m.debts
            ok &= list == [l for l in m.loans if l.borrower.id == id]  # === per element: Loan is mutable
        end
        ok &= all(haskey(m.debts, l.borrower.id) for l in m.loans)
        ok &= all(!isempty, values(m.debts))
        lenders = Dict{Int,Int}()
        for l in m.loans
            lenders[l.lender.id] = get(lenders, l.lender.id, 0) + 1
        end
        ok &= m.lent == lenders  # how many loans each lender has made, for skipping deaths without loans
        seen += length(m.loans)
    end
    @test ok && seen > 0
end
