# xxl (stage 4): the disease list switch, rule 12 (docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md).
# Three XxlRules settings, disease_count, founder_diseases and disease_lengths, set the config's disease_list,
# diseases_per_agent and disease_length. At nothing they leave the config as the experiment has it.
using Sugarscape, Test
using Sugarscape: run_extinction

@testset "xxl disease list: the switch" begin
    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1")
    ii4 = find_experiment(reg, "II-4")
    DL_LIST = (; disease_count=4, founder_diseases=2, disease_lengths=(9, 10))
    # The defaults with the experiment's own list: what XXL_DEFAULTS were before stage 4 adopted list D.
    OWN_LIST = replace_rules(XXL_DEFAULTS; disease_count=nothing, founder_diseases=nothing, disease_lengths=nothing)

    @testset "disease list: book settings change nothing" begin
        @test XXL_BOOK.disease_count === nothing &&
            XXL_V1.founder_diseases === nothing &&
            XXL_V1.disease_lengths === nothing
        c = to_xxl(vi1.config, OWN_LIST)
        @test (c.disease_list, c.diseases_per_agent, c.disease_length) == (25, 10, (1, 10))
        @test Sugarscape.rules_line(OWN_LIST) ==
            "vision_shape=\"disc\" speed=(1, 6) travel_cost=0.2 memory=8 memory_span=50 word_of_mouth=true " *
              "interaction_radius=1.5 season_gradient=true landscape=\"generated\" founder_placement=\"viable\" free_step=1.5"
        @test !occursin("disease_count", Sugarscape.xxl_fingerprint(vi1, OWN_LIST))
    end

    @testset "disease list: the defaults are list D" begin
        c = to_xxl(vi1.config, XXL_DEFAULTS)
        @test (c.disease_list, c.diseases_per_agent, c.disease_length) == (3, 1, (9, 10))
        @test endswith(Sugarscape.rules_line(XXL_DEFAULTS), "free_step=1.5 disease_count=3 founder_diseases=1 disease_lengths=(9, 10)")
        @test occursin("disease_count=3", Sugarscape.xxl_fingerprint(vi1, XXL_DEFAULTS))
        for id in ("V-1", "V-2", "VAR-inttrade/VI-1")  # the other experiments with disease take it too
            d = to_xxl(find_experiment(reg, id).config, XXL_DEFAULTS)
            @test (d.disease_list, d.diseases_per_agent, d.disease_length) == (3, 1, (9, 10))
        end
    end

    @testset "disease list: each setting reaches the config" begin
        c = to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; DL_LIST...))
        @test (c.disease_list, c.diseases_per_agent, c.disease_length) == (4, 2, (9, 10))
        @test c.xxl.disease_count == 4
        @test to_xxl(vi1.config, replace_rules(OWN_LIST; founder_diseases=5)).diseases_per_agent == 5
        @test to_xxl(vi1.config, replace_rules(OWN_LIST; disease_count=30)).disease_list == 30
        @test to_xxl(vi1.config, replace_rules(OWN_LIST; disease_lengths=(12, 12))).disease_length == (12, 12)
    end

    @testset "disease list: the founders it makes" begin
        m = Model(to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; DL_LIST...)))
        @test length(m.disease_list) == 4
        @test all(id -> 9 <= m.disease_len[id] <= 10, m.disease_list)
        @test all(a -> length(a.diseases) <= 2, m.agents)
        @test 1.8 <= sum(a -> length(a.diseases), m.agents) / length(m.agents) <= 2.0  # 2 offered, a few immune
        long = Model(to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; disease_count=4, founder_diseases=2, disease_lengths=(12, 12))))
        @test all(id -> m.disease_len[id] in (9, 10), m.disease_list) && all(id -> long.disease_len[id] == 12, long.disease_list)
        none = Model(to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; DL_LIST..., founder_diseases=0)))
        @test length(none.disease_list) == 4 && all(a -> isempty(a.diseases), none.agents)
    end

    @testset "disease list: refusals" begin
        for bad in (
            (; disease_count=0), (; disease_count=-1), (; founder_diseases=-1),
            (; disease_count=4, founder_diseases=5), (; disease_count=4),  # 10 offered of 4
            (; disease_lengths=(0, 10)), (; disease_lengths=(10, 9)), (; disease_lengths=(1, 50)),  # 50 reaches immune_length
        )
            @test_throws ArgumentError to_xxl(vi1.config, replace_rules(OWN_LIST; bad...))
        end
    end

    @testset "disease list: rules that skip to_xxl are refused" begin
        R0 = replace_rules(XXL_V1; season_gradient=false)
        for kw in ((; disease_count=25), (; founder_diseases=0), (; disease_lengths=(1, 10)))
            @test_throws ArgumentError replace_config(to_xl(ii4.config); xxl=replace_rules(R0; kw...))  # no disease to apply to
        end
        for kw in ((; disease_count=4, founder_diseases=2), (; founder_diseases=2), (; disease_lengths=(9, 10)))
            @test_throws ArgumentError replace_config(to_xl(vi1.config); xxl=replace_rules(R0; kw...))  # the config still says otherwise
        end
    end

    @testset "disease list: an experiment without disease resets them" begin
        c = to_xxl(ii4.config, replace_rules(XXL_V1; season_gradient=false, DL_LIST...))
        @test c.disease_list == 0 && c.xxl.disease_count === nothing && c.xxl.founder_diseases === nothing && c.xxl.disease_lengths === nothing
        @test Sugarscape.xxl_fingerprint(ii4, replace_rules(XXL_DEFAULTS; DL_LIST...)) == Sugarscape.xxl_fingerprint(ii4, XXL_DEFAULTS)
    end

    @testset "disease list: the fingerprint names a setting when it's on" begin
        @test endswith(Sugarscape.rules_line(replace_rules(XXL_DEFAULTS; DL_LIST...)),
                       "free_step=1.5 disease_count=4 founder_diseases=2 disease_lengths=(9, 10)")
        @test endswith(Sugarscape.rules_line(replace_rules(OWN_LIST; founder_diseases=2)), "free_step=1.5 founder_diseases=2")
        @test replace_rules(XXL_DEFAULTS; DL_LIST...) != XXL_DEFAULTS
        @test hash(replace_rules(XXL_DEFAULTS; DL_LIST...)) != hash(XXL_DEFAULTS)
    end

    @testset "disease list: naming the book's list gives the same bytes" begin
        a, b = mktempdir(), mktempdir()
        kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=vi1)
        run_extinction(OWN_LIST; kw..., out=a)
        run_extinction(replace_rules(OWN_LIST; disease_count=25, founder_diseases=10, disease_lengths=(1, 10)); kw..., out=b)
        name = Sugarscape.extinction_name("t", 20, 1, 12)
        @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
    end
end
