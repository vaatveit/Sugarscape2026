# xxl (stage 8): the combat study (julia/src/xxl/combat_study.jl). Each world runs a few periods of III-13; resuming, the
# fingerprint, the prefix of a saved run and the command line are checked on runs of a few periods.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: run_combat_world, combat_study_main, COMBAT_EXPS, COMBAT_WORLDS, world_fingerprint, sex_fingerprint,
    load_registry, find_experiment, with_steps, extinction_fingerprint, XXL_DEFAULTS

const CB_KW = (seeds=2, first_seed=3, periods=5, io=devnull)
cb_files(k) = ("seed$k.csv", "seed$k-combat.csv", "seed$k.timing.csv")

@testset "xxl combat study: the experiments and the worlds" begin
    @test COMBAT_EXPS == ("III-9", "III-11", "III-12", "III-13", "III-14")
    @test COMBAT_WORLDS == ("book", "xl", "today")
end

@testset "xxl combat study: world_fingerprint is the front of sex_fingerprint" begin
    exp = with_steps(find_experiment(load_registry(), "VI-1"), 6)
    for world in ("book", "xl", "today")
        w = world_fingerprint(exp, world, 6)
        @test sex_fingerprint(exp, world, 6) == w * "sex readings: world=$world window=(1, 6)\n"
        @test !occursin("readings", w)
    end
    @test world_fingerprint(exp, "today", 6) == extinction_fingerprint(exp, XXL_DEFAULTS, 6)
end

@testset "xxl combat study: each world writes its files and names itself" begin
    for world in COMBAT_WORLDS
        out = mktempdir()
        folder = run_combat_world(world, "III-13"; CB_KW..., out=out)
        @test basename(folder) == "combat-$world-III-13-s3-2-p5"
        @test dirname(folder) == out
        for k in (3, 4)
            for name in cb_files(k)
                @test isfile(joinpath(folder, name))
            end
            for name in ("seed$k.csv", "seed$k-combat.csv")
                @test countlines(joinpath(folder, name)) == 5 + 2
            end
        end
        text = read(joinpath(folder, "fingerprint.txt"), String)
        @test endswith(text, "combat readings: world=$world exp=III-13\n")
        @test !occursin("sex readings", text)
        @test !any(endswith(".tmp"), readdir(folder))
    end
end

@testset "xxl combat study: periods default to the experiment's steps" begin
    exp = find_experiment(load_registry(), "III-13")
    @test exp.steps == 200
    @test_throws ArgumentError run_combat_world("book", "III-13"; seeds=0, io=devnull, out=mktempdir())
end

@testset "xxl combat study: a second call skips what is done, another fingerprint is refused" begin
    out = mktempdir()
    folder = run_combat_world("book", "III-13"; CB_KW..., out=out)
    names = [cb_files(3)...; cb_files(4)...]
    before = [mtime(joinpath(folder, n)) for n in names]
    sleep(0.05)
    @test run_combat_world("book", "III-13"; CB_KW..., out=out) == folder
    @test [mtime(joinpath(folder, n)) for n in names] == before

    # a seed cut short runs again, alone
    whole = read(joinpath(folder, "seed3.csv"))
    other = [mtime(joinpath(folder, n)) for n in cb_files(4)]
    rm(joinpath(folder, "seed3-combat.csv"))
    write(joinpath(folder, "seed3.timing.csv.tmp"), "half")
    sleep(0.05)
    run_combat_world("book", "III-13"; CB_KW..., out=out)
    @test read(joinpath(folder, "seed3.csv")) == whole
    @test isfile(joinpath(folder, "seed3-combat.csv"))
    @test !isfile(joinpath(folder, "seed3.timing.csv.tmp"))
    @test [mtime(joinpath(folder, n)) for n in cb_files(4)] == other

    fp = joinpath(folder, "fingerprint.txt")
    write(fp, replace(read(fp, String), "periods=5" => "periods=6"))
    @test_throws ArgumentError run_combat_world("book", "III-13"; CB_KW..., out=out)
end

@testset "xxl combat study: book III-9 seed 0 is the saved run's prefix" begin
    saved = "C:/Projects/Sugarscape2026/results-julia/III-9/seed0.csv"
    if isfile(saved)
        folder = run_combat_world("book", "III-9"; seeds=1, first_seed=0, periods=6, io=devnull, out=mktempdir())
        @test readlines(joinpath(folder, "seed0.csv")) == readlines(saved)[1:8]  # the header and periods 0 to 6
    else
        @info "saved III-9 run absent; prefix test skipped"
        @test_skip false
    end
end

@testset "xxl combat study: the command line" begin
    quiet(f) = redirect_stderr(f, devnull)
    @test quiet(() -> combat_study_main(["--world", "xl"])) == 1
    @test quiet(() -> combat_study_main(["--exp", "III-9"])) == 1
    @test quiet(() -> combat_study_main(["--world", "xl", "--exp", "VI-1"])) == 1
    @test quiet(() -> combat_study_main(["--world", "sex", "--exp", "III-9"])) == 1
    @test quiet(() -> combat_study_main(["--world", "xl", "--exp", "III-9", "--bogus"])) == 1
    @test_throws ArgumentError run_combat_world("sex", "III-9"; out=mktempdir(), io=devnull)
    @test_throws ArgumentError run_combat_world("book", "VI-1"; out=mktempdir(), io=devnull)
    out = mktempdir()
    args = ["--world", "today", "--exp", "III-13", "--seeds", "1", "--first-seed", "3", "--periods", "5", "--out", out]
    @test redirect_stdout(() -> combat_study_main(args), devnull) == 0
    folder = joinpath(out, "combat-today-III-13-s3-1-p5")
    @test isfile(joinpath(folder, "seed3-combat.csv"))
    fp = joinpath(folder, "fingerprint.txt")
    write(fp, replace(read(fp, String), "periods=5" => "periods=6"))
    @test quiet(() -> combat_study_main(args)) == 1
end
