# xxl (stage 7): the culture study (julia/src/xxl/culture_study.jl). Each world runs a few periods of VI-1; resuming, the
# fingerprint and the command line are checked on runs of a few periods.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: run_culture_world, run_sex_world, culture_study_main, CULTURE_WORLDS, CULTURE_WINDOW, culture_window,
    read_seed_csv, RESULTS_XXL

const CS_KW = (seeds=2, first_seed=20, periods=6, io=devnull)
cs_files(k) = ("seed$k.csv", "seed$k-culture.csv", "seed$k-patches.csv", "seed$k.timing.csv")

@testset "xxl culture study: the window and the worlds" begin
    @test CULTURE_WORLDS == ("book", "xl", "today")
    @test CULTURE_WINDOW == 200
    @test culture_window(500) == (301, 500)
    @test culture_window(6) == (1, 6)
end

@testset "xxl culture study: each world writes its files and names itself" begin
    for world in CULTURE_WORLDS
        out = mktempdir()
        folder = run_culture_world(world; CS_KW..., out=out)
        @test basename(folder) == "culture-$world-VI-1-s20-2-p6"
        @test dirname(folder) == out
        for k in (20, 21)
            for name in cs_files(k)
                @test isfile(joinpath(folder, name))
            end
            for name in ("seed$k.csv", "seed$k-culture.csv")
                @test countlines(joinpath(folder, name)) == 6 + 2
            end
            header, M = read_seed_csv(joinpath(folder, "seed$k-culture.csv"))
            @test header[1] == "t" && M[:, 1] == 0.0:6.0
            header, P = read_seed_csv(joinpath(folder, "seed$k-patches.csv"))
            @test header[1] == "t" && all(==(0.0), P[:, 1])
            @test size(P, 1) > 0
        end
        text = read(joinpath(folder, "fingerprint.txt"), String)
        @test endswith(text, "periods=6\nculture readings: world=$world window=(1, 6)\n")
        @test !occursin("sex readings", text)
        @test occursin("code sha256=", text)
        @test count("periods=", text) == 1
        @test isfile(joinpath(folder, "machine.txt"))
        @test !any(endswith(".tmp"), readdir(folder))
    end
end

@testset "xxl culture study: a second call skips what is done, another fingerprint is refused" begin
    out = mktempdir()
    folder = run_culture_world("today"; CS_KW..., out=out)
    names = [cs_files(20)...; cs_files(21)...]
    before = [mtime(joinpath(folder, n)) for n in names]
    sleep(0.05)
    @test run_culture_world("today"; CS_KW..., out=out) == folder
    @test [mtime(joinpath(folder, n)) for n in names] == before

    write(joinpath(folder, "fingerprint.txt"), replace(read(joinpath(folder, "fingerprint.txt"), String), "periods=6" => "periods=7"))
    @test_throws ArgumentError run_culture_world("today"; CS_KW..., out=out)
end

@testset "xxl culture study: a seed cut short runs again, alone" begin
    out = mktempdir()
    folder = run_culture_world("xl"; CS_KW..., out=out)
    whole = read(joinpath(folder, "seed20.csv"))
    other = [mtime(joinpath(folder, n)) for n in cs_files(21)]
    rm(joinpath(folder, "seed20-patches.csv"))
    write(joinpath(folder, "seed20-culture.csv.tmp"), "half")
    sleep(0.05)
    run_culture_world("xl"; CS_KW..., out=out)
    @test read(joinpath(folder, "seed20.csv")) == whole
    @test isfile(joinpath(folder, "seed20-patches.csv"))
    @test !isfile(joinpath(folder, "seed20-culture.csv.tmp"))
    @test [mtime(joinpath(folder, n)) for n in cs_files(21)] == other
end

@testset "xxl culture study: the same model as the sex study" begin
    for world in ("book", "today")
        c = run_culture_world(world; seeds=1, first_seed=20, periods=6, io=devnull, out=mktempdir())
        s = run_sex_world(world; seeds=1, first_seed=20, periods=6, io=devnull, out=mktempdir())
        @test read(joinpath(c, "seed20.csv")) == read(joinpath(s, "seed20.csv"))
    end
end

@testset "xxl culture study: the command line" begin
    quiet(f) = redirect_stderr(f, devnull)
    @test quiet(() -> culture_study_main(["--world", "sex"])) == 1
    @test quiet(() -> culture_study_main(String[])) == 1
    @test quiet(() -> culture_study_main(["--world", "xl", "--bogus"])) == 1
    @test_throws ArgumentError run_culture_world("sex"; out=mktempdir(), io=devnull)
    out = mktempdir()
    args = ["--world", "today", "--seeds", "1", "--first-seed", "20", "--periods", "6", "--out", out]
    @test redirect_stdout(() -> culture_study_main(args), devnull) == 0
    folder = joinpath(out, "culture-today-VI-1-s20-1-p6")
    @test isfile(joinpath(folder, "seed20-culture.csv"))
    fp = joinpath(folder, "fingerprint.txt")
    write(fp, replace(read(fp, String), "periods=6" => "periods=7"))
    @test quiet(() -> culture_study_main(args)) == 1
end
