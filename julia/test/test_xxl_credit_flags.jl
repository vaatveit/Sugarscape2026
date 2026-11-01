# xxl: the credit study's options on the extinction test and the loan trace: the options value, the fingerprint and
# report that name them, the refusal of a folder run under other ones, and both command lines. Short runs of VI-1 into
# temporary folders, as test_xxl_extinction.jl does.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: CreditOptions, TraceWorld, run_extinction, extinction_main, loan_trace_main

const EXT2_VI1 = find_experiment(load_registry(), "VI-1")

@testset "credit flags: options" begin
    @test Sugarscape.options_text(CreditOptions()) == ""
    @test Sugarscape.options_text(CreditOptions(; credit_off=true, inheritance=true)) == "credit off, inheritance"
    e = find_experiment(load_registry(), "VI-1")
    @test Sugarscape.with_options(e, CreditOptions()) === e
    off = Sugarscape.with_options(e, CreditOptions(; credit_off=true))
    @test off.config.credit === nothing && off.xl_config.credit === nothing
    reach = Sugarscape.with_options(e, CreditOptions(; credit_reach=2.0, lender_limit=true))
    @test reach.config.credit_reach == 2.0 && reach.config.lender_limit && reach.config.credit == e.config.credit
end

@testset "credit flags: the fingerprint changes only when an option does" begin
    r, e = XXL_DEFAULTS, find_experiment(load_registry(), "VI-1")
    plain = Sugarscape.extinction_plan(r, e, "o", "l", 20, 1, 12)
    same = Sugarscape.extinction_plan(r, e, "o", "l", 20, 1, 12; options=CreditOptions())
    off = Sugarscape.extinction_plan(r, e, "o", "l", 20, 1, 12; options=CreditOptions(; credit_off=true))
    @test plain.fingerprint == same.fingerprint
    @test !occursin("credit options", plain.fingerprint)
    @test occursin("credit options: credit off\n", off.fingerprint)
end

@testset "credit flags: a change of flag refuses the folder" begin
    out = mktempdir()
    kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, out=out, io=devnull, experiment=EXT2_VI1)
    run_extinction(XXL_DEFAULTS; kw..., options=CreditOptions(; credit_off=true))
    @test_throws ArgumentError run_extinction(XXL_DEFAULTS; kw...)
    @test_throws ArgumentError run_extinction(XXL_DEFAULTS; kw..., options=CreditOptions(; inheritance=true))
end

@testset "credit flags: options off, the same bytes" begin
    a, b = mktempdir(), mktempdir()
    kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=EXT2_VI1)
    run_extinction(XXL_DEFAULTS; kw..., out=a)
    run_extinction(XXL_DEFAULTS; kw..., out=b, options=CreditOptions())
    name = Sugarscape.extinction_name("t", 20, 1, 12)
    @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
end

@testset "credit flags: an option changes the run" begin
    a, b = mktempdir(), mktempdir()
    kw = (label="t", seeds=1, first_seed=20, periods=40, jobs=1, io=devnull, experiment=EXT2_VI1)
    run_extinction(XXL_DEFAULTS; kw..., out=a)
    run_extinction(XXL_DEFAULTS; kw..., out=b, options=CreditOptions(; credit_off=true))
    name = Sugarscape.extinction_name("t", 20, 1, 40)
    @test read(joinpath(a, name, "seed20.csv")) != read(joinpath(b, name, "seed20.csv"))
end

@testset "credit flags: claims outlive the lender through a stop and resume" begin
    whole, broken = mktempdir(), mktempdir()
    o = CreditOptions(; claims_outlive_lender=true)
    kw = (label="t", seeds=1, first_seed=20, periods=40, jobs=1, io=devnull, experiment=EXT2_VI1, options=o)
    run_extinction(XXL_DEFAULTS; kw..., out=whole)
    @test run_extinction(XXL_DEFAULTS; kw..., out=broken, stop_at=25, checkpoint_every=10) === nothing
    run_extinction(XXL_DEFAULTS; kw..., out=broken, checkpoint_every=10)
    name = Sugarscape.extinction_name("t", 20, 1, 40)
    @test read(joinpath(whole, name, "seed20.csv")) == read(joinpath(broken, name, "seed20.csv"))
end

@testset "credit flags: the report names the options" begin
    out = mktempdir()
    o = CreditOptions(; credit_off=true)
    run_extinction(XXL_DEFAULTS; label="t", seeds=1, first_seed=20, periods=12, jobs=1, out=out, io=devnull,
                   experiment=EXT2_VI1, options=o)
    report = read(joinpath(out, Sugarscape.extinction_name("t", 20, 1, 12) * ".md"), String)
    @test occursin("- Credit options: credit off", report)
end

@testset "credit flags: the extinction command line" begin
    usage(args) = redirect_stderr(() -> extinction_main(args), devnull)
    for args in (
        ["--credit-reach"], ["--credit-reach", "0"], ["--credit-reach", "x"],
        ["--claims-outlive-lender", "--inheritance"], ["--no-credit", "--lender-limit"],
        ["--no-credit", "--credit-reach", "2"], ["--no-credit", "--claims-outlive-lender"],
    )
        @test usage([args; "--out"; mktempdir()]) == 2
    end
    a = Sugarscape.extinction_args(["--no-credit", "--inheritance"])
    @test a.options == CreditOptions(; credit_off=true, inheritance=true)
    a = Sugarscape.extinction_args(["--claims-outlive-lender", "--credit-reach", "2", "--lender-limit"])
    @test a.options == CreditOptions(; claims_outlive_lender=true, credit_reach=2.0, lender_limit=true)
end

@testset "credit flags: the loan trace" begin
    w = Sugarscape.loan_trace_args(["--credit-reach", "2", "--lender-limit"]).w
    @test w.credit_reach == 2.0 && w.lender_limit
    plain = TraceWorld("defaults", (10, 10.0), false)
    @test plain.credit_reach == 1.0 && !plain.lender_limit
    e = Sugarscape.trace_experiment(w, 12; experiment=EXT2_VI1)
    @test e.config.credit_reach == 2.0 && e.xl_config.lender_limit
    fp(x) = Sugarscape.trace_fingerprint(Sugarscape.trace_experiment(x, 12; experiment=EXT2_VI1), x, 12)
    @test !occursin("credit_reach", fp(plain)) && occursin("credit_reach=2.0\nlender_limit=true\n", fp(w))
    @test occursin("credit reach 2.0", Sugarscape.world_text(w)) && occursin("lender limit", Sugarscape.world_text(w))
    usage(args) = redirect_stderr(() -> loan_trace_main(args), devnull)
    @test usage(["--no-credit", "--credit-reach", "2"]) == 2
    @test usage(["--no-credit", "--lender-limit"]) == 2
    @test usage(["--credit-reach", "0"]) == 2
end
