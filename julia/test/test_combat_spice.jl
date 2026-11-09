# Rule C_alpha with spice and credit in the book's move (docs/superpowers/specs/2026-11-08-vi1-combat-design.md, "The
# rule"): wealth is sugar plus spice, the loot both goods, the site valued by the book's welfare score.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

# combat_model with the second commodity: spice capacity is zero (the mirror of a zero sugar map) unless a test sets it.
function spice_combat_model(alpha=Inf; kw...)
    return tiny_model(
        zeros(Int, 12, 12); tag_length=1, combat_alpha=alpha, vision=(1, 4), spice=true, kw...
    )
end

function spice_agent(m, x, y, tag, sugar, spice; vision=4)
    a = tag!(put_agent(m, x, y; vision=vision, sugar=sugar), [tag])
    a.spice, a.spice_metabolism = spice, 1
    return a
end

@testset "test_takes_all_sugar_and_spice" begin
    m = spice_combat_model()
    a = spice_agent(m, 1, 1, 0, 20.0, 20.0)
    r = spice_agent(m, 3, 1, 1, 8.0, 5.0)
    combat_move!(m, a)
    @test !r.alive && a.sugar == 28.0 && a.spice == 25.0 && (a.x, a.y) == (3, 1)
end

@testset "test_alpha_caps_each_good" begin
    m = spice_combat_model(2.0)
    a = spice_agent(m, 1, 1, 0, 20.0, 20.0)
    r = spice_agent(m, 3, 1, 1, 8.0, 5.0)
    combat_move!(m, a)
    @test !r.alive && a.sugar == 22.0 && a.spice == 22.0
end

@testset "test_wealthier_by_both_goods_not_attacked" begin
    m = spice_combat_model()
    a = spice_agent(m, 1, 1, 0, 20.0, 1.0)
    r = spice_agent(m, 3, 1, 1, 5.0, 20.0)  # less sugar, more wealth: 25 > 21
    combat_move!(m, a)
    @test r.alive
end

@testset "test_retaliation_counts_spice" begin
    m = spice_combat_model()
    a = spice_agent(m, 1, 1, 0, 20.0, 20.0)
    r = spice_agent(m, 3, 1, 1, 8.0, 5.0)
    spice_agent(m, 5, 1, 1, 10.0, 60.0)  # wealth 70 > 40 + 13; its sugar alone, 10 < 28, would not block
    combat_move!(m, a)
    @test r.alive && (a.x, a.y) != (3, 1)
end

@testset "test_loot_on_bare_site_counts" begin  # Review Focus 1: the w0 shortcut must not hide the loot
    m = spice_combat_model()
    a = spice_agent(m, 1, 1, 0, 20.0, 0.5)  # short of spice
    r = spice_agent(m, 3, 1, 1, 0.0, 6.0)  # on a bare site; wealth 6 <= 20.5
    m.landscape.sugar[2, 4] = 3.0  # empty site (1, 3), at the same distance
    combat_move!(m, a)
    @test (a.x, a.y) == (3, 1) && !r.alive
end

@testset "test_income_excludes_loot" begin
    m = spice_combat_model()
    a = spice_agent(m, 1, 1, 0, 20.0, 20.0)
    r = spice_agent(m, 3, 1, 1, 8.0, 5.0)
    m.landscape.sugar[4, 2] = 4.0  # the victim's site
    combat_move!(m, a)
    @test !r.alive && a.last_income == 4.0 && a.sugar == 32.0
end

@testset "test_victim_loans_settled_as_on_death" begin  # Review Focus 2
    function loan_world()
        m = spice_combat_model(; sex=true, credit=(10, 10.0))
        a = spice_agent(m, 1, 1, 0, 20.0, 20.0)
        r = spice_agent(m, 3, 1, 1, 8.0, 5.0)
        c = spice_agent(m, 8, 8, 0, 30.0, 30.0)  # the attacker's tribe, out of the way
        m.landscape.sugar[4, 2] = 4.0  # the victim's site
        m.landscape.spice[4, 2] = 2.0
        Sugarscape.add_loan!(m, Loan(a, r, 3.0, 3.3, m.t + 10))  # the victim borrowed from the attacker
        Sugarscape.add_loan!(m, Loan(c, a, 5.0, 5.5, m.t + 10))  # stands
        Sugarscape.add_loan!(m, Loan(r, c, 2.0, 2.2, m.t + 10))  # owed to the victim
        return m, a, r
    end
    book(m) = [(l.borrower.id, l.lender.id, l.principal, l.due, l.due_t) for l in m.loans]
    ma, a_a, r_a = loan_world()
    combat_move!(ma, a_a)
    mb, a_b, r_b = loan_world()
    die!(mb, r_b)
    @test !r_a.alive && !r_b.alive
    @test book(ma) == book(mb) && length(book(ma)) == 1
    @test a_a.sugar == a_b.sugar + 8.0 + 4.0 && a_a.spice == a_b.spice + 5.0 + 2.0
end

@testset "test_combat_with_spice_and_credit_validates" begin
    # Config() alone does not validate; validate is where the bars were (Model calls it)
    c = validate(Config(; spice=true, sex=true, combat_alpha=Inf, credit=(10, 10.0), tag_length=11))
    @test c.combat_alpha == Inf && c.spice && c.credit == (10, 10.0)
end
