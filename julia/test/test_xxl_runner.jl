# xxl: the runner's --xxl mode, the XXL-... experiments and their fingerprints (spec, "Runner and experiments").
using Sugarscape, Test

const XREG = load_registry()
const XTINY = find_experiment(XREG, "TEST-tiny")

@testset "xxl runner" begin
    @testset "main refuses --xxl with --xl before running anything" begin
        @test Sugarscape.main(["II-4", "--xxl", "--xl"]) == 2
        @test Sugarscape.main(["XXL-vision", "--xl"]) == 2
        @test Sugarscape.main(["no-such-id", "--xxl"]) == 2
    end

    @testset "a 2-seed --xxl run writes 46 + 9 columns and the xxl fingerprint" begin
        out = mktempdir()
        @test Sugarscape.main(["TEST-tiny", "--xxl", "--seeds", "2", "--out", out]) == 0
        folder = joinpath(out, "TEST-tiny")
        @test sort(readdir(folder)) ==
            ["fingerprint.txt", "machine.txt", "seed0.csv", "seed1.csv", "timing.csv"]
        for k in 0:1
            lines = readlines(joinpath(folder, "seed$k.csv"))
            @test length(lines) == 7  # header, t = 0..5
            header = split(lines[1], ",")
            @test length(header) == 46 + 9
            @test header == ["t"; METRIC_COLUMNS; XXL_METRIC_COLUMNS]
            @test all(length(split(l, ",")) == 55 for l in lines[2:end])
        end
        fp = read(joinpath(folder, "fingerprint.txt"), String)
        @test startswith(
            Sugarscape.xxl_fingerprint(XTINY, XXL_V1),
            "julia\nxxl vision_shape=\"disc\" speed=(1, 6) travel_cost=0.1 ",
        )
        @test fp == Sugarscape.xxl_fingerprint(XTINY, XXL_DEFAULTS)
        timing = readlines(joinpath(folder, "timing.csv"))
        @test length(timing) == 3 && startswith(timing[2], "0,5,")
    end

    @testset "the fingerprint" begin
        line = Sugarscape.rules_line(XXL_V1)
        @test line ==
            "vision_shape=\"disc\" speed=(1, 6) travel_cost=0.1 memory=8 memory_span=50 " *
              "word_of_mouth=true interaction_radius=1.5 season_gradient=true landscape=\"xl\""
        @test startswith(
            Sugarscape.rules_line(XXL_BOOK), "vision_shape=\"lattice\" speed=nothing "
        )
        fp = Sugarscape.xxl_fingerprint(XTINY, XXL_V1)
        # TEST-tiny has no seasons, so the gradient that did not apply is not named.
        @test startswith(fp, "julia\nxxl ") && occursin("season_gradient=false", fp)
        @test occursin("\n" * XTINY.xl_fingerprint, fp)
        @test !occursin("xxl map", fp)
    end

    @testset "runner reduction: xxl at book settings is the xl run" begin
        ii4 = find_experiment(XREG, "II-4")
        short = Experiment(
            ii4.id,
            ii4.title,
            ii4.rules,
            20,
            ii4.seeds,
            ii4.config,
            ii4.fingerprint,
            ii4.xl_config,
            ii4.xl_fingerprint,
        )
        a, _ = Sugarscape.timed_seed(short, 0; xxl=XXL_BOOK)
        b, _ = Sugarscape.timed_seed(short, 0; xl=true)
        @test length(a) == length(b) == 21
        @test all(length(r) == 55 for r in a) && all(length(r) == 46 for r in b)
        @test all(isequal(ra[1:46], rb[1:46]) for (ra, rb) in zip(a, b))
        @test_throws ArgumentError Sugarscape.timed_seed(short, 0; xl=true, xxl=XXL_BOOK)
    end

    @testset "seed_job passes xxl only when it is set" begin
        stand_in(exp, k; xl=false) = ([[0.0]], (; seed=k))
        r = Sugarscape.seed_job(XTINY, 0, false, stand_in)
        @test r[1] == [[0.0]]
        with_xxl(exp, k; xl=false, xxl=nothing) =
            ([[xxl === XXL_BOOK ? 1.0 : 0.0]], (; seed=k))
        r = Sugarscape.seed_job(XTINY, 0, false, with_xxl; xxl=XXL_BOOK)
        @test r[1] == [[1.0]]
    end

    @testset "the XXL experiments" begin
        ids = [id for (id, _, _) in Sugarscape.XXL_EXPERIMENTS]
        @test length(ids) == 16 && allunique(ids)
        @test Sugarscape.xxl_matching_ids("XXL") == ids
        @test Sugarscape.xxl_matching_ids("XXL-speed") ==
            ["XXL-speed/c0", "XXL-speed/c0.05", "XXL-speed/c0.1", "XXL-speed/c0.2"]
        @test Sugarscape.xxl_matching_ids("XXL-vision") == ["XXL-vision"]
        @test Sugarscape.xxl_matching_ids("XXL-terrain/II-4") == ["XXL-terrain/II-4"]
        @test isempty(Sugarscape.xxl_matching_ids("XXL-spe"))
        @test isempty(Sugarscape.xxl_matching_ids("II-4"))

        exp, rules = Sugarscape.xxl_experiment(XREG, "XXL-speed/c0.05")
        @test exp.id == "XXL-speed/c0.05" && exp.seeds == 5
        @test startswith(exp.title, "xxl: ")
        @test rules.travel_cost == 0.05 &&
            rules.speed == (1, 6) &&
            rules.vision_shape == "disc"
        @test rules.memory == 0 && !rules.word_of_mouth && rules.interaction_radius == 1.0
        @test to_xxl(exp.config, rules).xxl.travel_cost == 0.05
        base = find_experiment(XREG, "II-4")
        @test exp.steps == base.steps && exp.config == base.config
        @test exp.xl_fingerprint == base.xl_fingerprint
        @test_throws ArgumentError Sugarscape.xxl_experiment(XREG, "XXL-nope")

        table = Dict(id => (b, r) for (id, b, r) in Sugarscape.XXL_EXPERIMENTS)
        @test table["XXL-vision"] == ("II-4", replace_rules(XXL_BOOK; vision_shape="disc"))
        disc_speed(c) =
            replace_rules(XXL_BOOK; vision_shape="disc", speed=(1, 6), travel_cost=c)
        @test table["XXL-speed/c0"][2] == disc_speed(0.0)
        @test table["XXL-speed/c0.2"][2] == disc_speed(0.2)
        @test table["XXL-memory/solo"] == ("II-4", replace_rules(disc_speed(0.1); memory=8))
        @test table["XXL-memory/shared"] ==
            ("II-4", replace_rules(disc_speed(0.1); memory=8, word_of_mouth=true))
        for (id, r) in (("R1", 1.0), ("R1.5", 1.5), ("R3", 3.0))
            @test table["XXL-radius/$id"] ==
                ("IV-A3", replace_rules(XXL_V1; interaction_radius=r))
        end
        @test table["XXL-seasons/halves"] ==
            ("II-7", replace_rules(XXL_V1; season_gradient=false))
        @test table["XXL-seasons/gradient"] == ("II-7", XXL_V1)
        @test table["XXL-terrain/II-4"] ==
            ("II-4", replace_rules(XXL_V1; landscape="generated"))
        @test table["XXL-terrain/IV-A3"] ==
            ("IV-A3", replace_rules(XXL_V1; landscape="generated"))
        @test table["XXL-society/VI-1"] == ("VI-1", XXL_V1)
        @test table["XXL-combat/III-9"] == ("III-9", XXL_V1)

        # Every one of them is a valid config over its base.
        for id in ids
            e, r = Sugarscape.xxl_experiment(XREG, id)
            @test validate(to_xxl(e.config, r)) isa Config
        end
    end

    @testset "fingerprints name the generated maps in use" begin
        both, rules = Sugarscape.xxl_experiment(XREG, "XXL-terrain/IV-A3")
        fp = Sugarscape.xxl_fingerprint(both, rules)
        @test occursin("landscape=\"generated\"", fp)
        @test occursin(
            "\nxxl map sugar-map-xxl.txt sha256=$(map_sha256("sugar-map-xxl.txt"))\n", fp
        )
        @test occursin(
            "\nxxl map spice-map-xxl.txt sha256=$(map_sha256("spice-map-xxl.txt"))\n", fp
        )

        sugar_only, rules = Sugarscape.xxl_experiment(XREG, "XXL-terrain/II-4")
        fp = Sugarscape.xxl_fingerprint(sugar_only, rules)
        @test occursin(
            "\nxxl map sugar-map-xxl.txt sha256=$(map_sha256("sugar-map-xxl.txt"))\n", fp
        )
        @test !occursin("spice-map-xxl", fp)

        plain, rules = Sugarscape.xxl_experiment(XREG, "XXL-vision")
        @test !occursin("xxl map", Sugarscape.xxl_fingerprint(plain, rules))
    end

    @testset "an XXL id runs into results-julia-xxl without --xxl" begin
        @test Sugarscape.RESULTS_XXL == "results-julia-xxl"
        @test occursin(
            "results-julia-xxl/", read(joinpath(@__DIR__, "..", "..", ".gitignore"), String)
        )
    end
end
