# xxl: --set on the extinction test (the disease list's three settings among the rules it can set): the shared reading
# of field=value, the label, the refusals as usage errors on both tools, and a folder that a different --set refuses.
# Short runs of VI-1 into temporary folders, as test_xxl_credit_flags.jl does.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: run_extinction

@testset "xxl disease list flags" begin
    vi1 = find_experiment(load_registry(), "VI-1")
    list = replace_rules(XXL_DEFAULTS; disease_count=4, founder_diseases=2, disease_lengths=(9, 10))

    @testset "--set parses on both tools" begin
        args = ["--set", "disease_count=4", "--set", "founder_diseases=2", "--set", "disease_lengths=9,10"]
        @test Sugarscape.scorecard_args(args).rules == list
        a = Sugarscape.extinction_args(args)
        @test a.rules == list
        @test a.label == "defaults+disease_count=4+founder_diseases=2+disease_lengths=9,10"
        @test Sugarscape.extinction_args(["--set", "disease_count=nothing"]).rules == XXL_DEFAULTS
        @test Sugarscape.extinction_args(String[]).label == "defaults"
        @test Sugarscape.extinction_args(["--rules", "v1", "--set", "free_step=1.5", "--label", "x"]).label == "x"
    end

    @testset "refusals are usage errors" begin
        usage(f, args) = redirect_stderr(() -> f(args), devnull)
        for args in (["--set"], ["--set", "nofield=1"], ["--set", "disease_count"], ["--set", "disease_count=x"],
                     ["--set", "disease_lengths=9"], ["--set", "disease_count=4"], ["--set", "disease_count=0"])
            @test usage(Sugarscape.extinction_main, [args; "--out"; mktempdir()]) == 2
            @test usage(Sugarscape.scorecard_main, [args; "--out"; mktempdir()]) == 2
        end
    end

    @testset "a different --set refuses the folder" begin
        out = mktempdir()
        kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, out=out, io=devnull, experiment=vi1)
        run_extinction(list; kw...)
        @test_throws ArgumentError run_extinction(XXL_DEFAULTS; kw...)
        @test_throws ArgumentError run_extinction(replace_rules(list; disease_count=5); kw...)
        @test_throws ArgumentError Sugarscape.rebuild_extinction_report(
            XXL_DEFAULTS; label="t", seeds=1, first_seed=20, periods=12, out=out, experiment=vi1, io=devnull,
        )
        @test Sugarscape.rebuild_extinction_report(
            list; label="t", seeds=1, first_seed=20, periods=12, out=out, experiment=vi1, io=devnull,
        ).extinct == 0
        report = read(joinpath(out, Sugarscape.extinction_name("t", 20, 1, 12) * ".md"), String)
        @test occursin("disease_count=4 founder_diseases=2 disease_lengths=(9, 10)", report)
    end

    @testset "--report-only with --set, through extinction_main" begin
        # A real 4-period run of VI-1 (extinction_main always reads the real one) into a folder, and then its report rebuilt:
        # with the same --set it is 0; with none, or another, the fingerprint differs and it is a usage error.
        out = mktempdir()
        base_args = ["--label", "t", "--seeds", "1", "--first-seed", "20", "--periods", "4", "--jobs", "1", "--out", out]
        set_args(count; lengths="9,10") = ["--set", "disease_count=$count", "--set", "founder_diseases=2",
                                           "--set", "disease_lengths=$lengths"]
        quiet(f) = redirect_stdout(() -> redirect_stderr(f, devnull), devnull)
        run_main(extra) = quiet(() -> Sugarscape.extinction_main([base_args; extra]))
        @test run_main(set_args(4)) == 0
        @test run_main([set_args(4); "--report-only"]) == 0                          # the same --set
        @test run_main(["--report-only"]) == 2                                       # none
        @test run_main([set_args(5); "--report-only"]) == 2                          # another count
        @test run_main([set_args(4; lengths="8,10"); "--report-only"]) == 2          # another length
    end

    @testset "a list through a stop and resume" begin
        whole, broken = mktempdir(), mktempdir()
        kw = (label="t", seeds=1, first_seed=20, periods=40, jobs=1, io=devnull, experiment=vi1)
        run_extinction(list; kw..., out=whole)
        @test run_extinction(list; kw..., out=broken, stop_at=25, checkpoint_every=10) === nothing
        run_extinction(list; kw..., out=broken, checkpoint_every=10)
        name = Sugarscape.extinction_name("t", 20, 1, 40)
        @test read(joinpath(whole, name, "seed20.csv")) == read(joinpath(broken, name, "seed20.csv"))
    end
end
