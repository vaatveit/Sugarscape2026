# Ports tests/test_disease_model.py.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

function disease_model(; kw...)
    return Model(Config(; disease_list=10, diseases_per_agent=4, seed=1, kw...))
end
db(s) = bits([c == '1' ? 1 : 0 for c in s])
function immunise!(a, s)
    a.immune, a.immune_genotype, a.nimmune, a.disease_fee = db(s), db(s), length(s), 1.0
    return a
end

@testset "test_master_list_and_initial_infection" begin  # p.147
    m = disease_model()
    @test length(m.disease_list) == 10 &&
        all(1 <= m.disease_len[d] <= 10 for d in m.disease_list)
    @test all(a.nimmune == 50 && a.immune == a.immune_genotype for a in m.agents)
    @test all(length(a.diseases) <= 4 && allunique(a.diseases) for a in m.agents)
    @test all(
        !is_immune(a.immune, a.nimmune, m.disease_bits[d], m.disease_len[d]) for
        a in m.agents for d in a.diseases
    )
    @test any(!isempty(a.diseases) for a in m.agents) &&
        all(a.disease_fee == 1.0 for a in m.agents)
    @test all(a.immune >> 50 == 0 for a in m.agents)
end

@testset "test_phenotype_trains_genotype_does_not" begin  # p.146
    m = disease_model()
    a = m.agents[findfirst(a -> !isempty(a.diseases), m.agents)]
    before = a.immune_genotype
    for _ in 1:12
        immune_response!(m, a)
    end
    @test a.immune_genotype == before && a.immune != before
end

@testset "test_transmission_logs_new_infections" begin  # p.145, p.150
    m = tiny_model(
        ones(Int, 5, 5); disease_list=1, diseases_per_agent=0, disease_length=(3, 3)
    )
    sick = immunise!(put_agent(m, 2, 2), "0000000000")
    well = immunise!(put_agent(m, 2, 3), "0000000000")
    d = intern_disease!(m, db("111"), 3)
    sick.diseases = [d]
    disease_transmit!(m, sick)
    @test well.diseases == [d] && m.infection_log == [(sick, well)]
    disease_transmit!(m, sick)
    @test m.infection_log == [(sick, well)]  # already carried: no new infection
end

@testset "test_fee_raises_burn_and_changes_behaviour" begin  # p.143
    m = tiny_model(ones(Int, 5, 5); spice=true, disease_list=1, diseases_per_agent=0)
    a = put_agent(m, 2, 2; sugar=10.0)
    a.spice, a.spice_metabolism, a.disease_fee = 10.0, 1, 1.0
    healthy = mrs(a)
    a.diseases = [intern_disease!(m, db("1"), 1), intern_disease!(m, db("0"), 1)]
    @test sugar_burn(a) == a.metabolism + 2.0 && mrs(a) > healthy
    metabolize!(m, a)
    @test a.sugar == 10.0 - (a.metabolism + 2.0)
end

@testset "test_children_inherit_crossed_genotype_without_diseases" begin  # p.146
    m = tiny_model(ones(Int, 6, 6); sex=true, disease_list=2, diseases_per_agent=0)
    f, h = couple(m)
    immunise!(f, repeat("0011", 13))
    immunise!(h, repeat("0101", 13))
    f.diseases = [intern_disease!(m, db("11"), 2)]
    child = mate!(m, f)[1]
    @test all((child.immune_genotype >> (4 * k)) & 1 == 0 for k in 0:12)  # agreeing 0s copied
    @test all((child.immune_genotype >> (4 * k + 3)) & 1 == 1 for k in 0:12)  # agreeing 1s copied
    @test child.immune == child.immune_genotype &&
        child.nimmune == 52 &&
        isempty(child.diseases)
    @test child.disease_fee == 1.0
end

@testset "test_replacements_are_healthy_with_random_immunity" begin
    cfg = Config(;
        disease_list=10,
        diseases_per_agent=4,
        max_age=(1, 1),
        replacement=true,
        initial_population=30,
        seed=3,
    )
    m = Model(cfg)
    step!(m)
    @test all(isempty(a.diseases) && a.nimmune == 50 for a in m.agents)
end

@testset "test_sick_society_runs" begin
    m = Model(Config(; disease_list=25, diseases_per_agent=10, endowment=(25, 50), seed=2))
    run!(m, 30)
    @test all(a.alive && allunique(a.diseases) for a in m.agents)
    @test all(t.alive for (_, t) in m.infection_log)
end

@testset "test_one_bit_disease_is_passed_on_before_it_is_learned" begin  # p.143
    m = tiny_model(ones(Int, 5, 5); disease_list=1, diseases_per_agent=0)
    sick = immunise!(put_agent(m, 2, 2), "1100000000")
    sick.immune_genotype = db("0000000000")
    well = immunise!(put_agent(m, 2, 3), "0000000000")
    d = intern_disease!(m, db("111"), 3)
    sick.diseases = [d]  # one bit from sick's window 110
    step!(m)
    @test isempty(sick.diseases) && well.diseases[1:1] == [d]
end
