# xxl (stage 5): the trade-off option of the study runs. CreditOptions(; trade_off=true) turns trade off in the world an
# extinction run starts from; Rule 13 then has nothing to count on and is reset (docs/superpowers/specs/2026-11-03-xxl-trade-design.md).
using Sugarscape, Test
using Sugarscape: run_extinction, CreditOptions, with_options, extinction_fingerprint, options_text, validate

@testset "xxl trade off: the study option" begin
    reg = load_registry()
    vi1 = find_experiment(reg, "VI-1")
    OFF = CreditOptions(; trade_off=true)
    LOCAL = replace_rules(XXL_DEFAULTS; trade_move="local")

    @testset "trade off: with_options turns trade off in both configs, and VI-1 still validates" begin
        @test vi1.config.trade && vi1.xl_config.trade
        off = with_options(vi1, OFF)
        @test off.config.trade == false && off.xl_config.trade == false
        @test (validate(off.config); validate(off.xl_config); true)  # validate throws if it refuses
        @test CreditOptions() == CreditOptions(; trade_off=false)
        @test with_options(vi1, CreditOptions()) === vi1
        # the other options are left as they were
        both = with_options(vi1, CreditOptions(; trade_off=true, credit_off=true))
        @test both.config.trade == false && both.config.credit === nothing
    end

    @testset "trade off: the fingerprint names it only when it is on" begin
        fp(o) = extinction_fingerprint(vi1, XXL_DEFAULTS, 12; options=o)
        @test occursin("trade: off\n", fp(OFF))
        @test !occursin("trade: off", fp(CreditOptions()))
        @test !occursin("credit options", fp(CreditOptions()))
        # credit off: its line is as it was and no trade line
        coff = fp(CreditOptions(; credit_off=true))
        @test occursin("credit options: credit off\n", coff)
        @test !occursin("trade: off", coff)
        # with both, the trade line follows the credit-options line
        both = fp(CreditOptions(; credit_off=true, trade_off=true))
        @test occursin("credit options: credit off\ntrade: off\n", both)
        # trade off alone has no credit-options line, and options_text is unchanged by it
        @test !occursin("credit options", fp(OFF))
        @test options_text(OFF) == ""
        @test fp(OFF) != fp(CreditOptions())
    end

    @testset "trade off: rule 13 is reset" begin
        c = to_xxl(with_options(vi1, OFF).config, LOCAL)
        @test c.xxl.trade_move === nothing && c.xxl.trade_blend == 1.0 && c.xxl.trade_guard === nothing
    end

    @testset "trade off: rule 13 with it gives the same bytes as trade off alone" begin
        a, b = mktempdir(), mktempdir()
        kw = (label="t", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=vi1, options=OFF)
        run_extinction(XXL_DEFAULTS; kw..., out=a)
        run_extinction(LOCAL; kw..., out=b)
        name = Sugarscape.extinction_name("t", 20, 1, 12)
        @test read(joinpath(a, name, "seed20.csv")) == read(joinpath(b, name, "seed20.csv"))
    end

    @testset "trade off: no trades in a run" begin
        dir = mktempdir()
        run_extinction(XXL_DEFAULTS; label="t", seeds=1, first_seed=20, periods=12, jobs=1, io=devnull, experiment=vi1,
                       options=OFF, out=dir)
        lines = readlines(joinpath(dir, Sugarscape.extinction_name("t", 20, 1, 12), "seed20.csv"))
        header = split(lines[1], ',')
        col = findfirst(==("trades"), header)
        @test col !== nothing
        @test length(lines) == 14
        @test all(l -> parse(Float64, split(l, ',')[col]) == 0, lines[2:end])
    end
end
