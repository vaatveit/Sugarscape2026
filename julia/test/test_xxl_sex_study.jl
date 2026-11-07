# xxl (stage 6): the sex study (julia/src/xxl/sex_study.jl). Each world runs a few periods of VI-1; resuming, the
# fingerprint and the command line are checked on runs of a few periods.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape: run_sex_world, sex_study_args, sex_study_main, sex_name, sex_window, SEX_WORLDS, read_seed_csv, RESULTS_XXL

const SS_KW = (seeds=2, first_seed=20, periods=6, io=devnull)
ss_files(k) = ("seed$k.csv", "seed$k-sex.csv", "seed$k-agents.csv", "seed$k.timing.csv")

@testset "xxl sex study: the window, the name and the worlds" begin
    @test SEX_WORLDS == ("book", "xl", "today")
    @test sex_window(500) == (301, 500)
    @test sex_window(6) == (1, 6)
    @test sex_name("xl", 80, 20, 500) == "sex-xl-VI-1-s80-20-p500"
end

@testset "xxl sex study: each world writes its files and names itself" begin
    for world in SEX_WORLDS
        out = mktempdir()
        folder = run_sex_world(world; SS_KW..., out=out)
        @test basename(folder) == "sex-$world-VI-1-s20-2-p6"
        @test dirname(folder) == out
        for k in (20, 21)
            for name in ss_files(k)
                @test isfile(joinpath(folder, name))
            end
            for name in ("seed$k.csv", "seed$k-sex.csv")
                @test countlines(joinpath(folder, name)) == 6 + 2
            end
            header, M = read_seed_csv(joinpath(folder, "seed$k-sex.csv"))
            @test header[1] == "t" && M[:, 1] == 0.0:6.0
            @test read_seed_csv(joinpath(folder, "seed$k-agents.csv"))[1][1] == "id"
        end
        text = read(joinpath(folder, "fingerprint.txt"), String)
        @test endswith(text, "periods=6\nsex readings: world=$world window=(1, 6)\n")
        @test occursin("code sha256=", text)
        @test count("periods=", text) == 1
        @test isfile(joinpath(folder, "machine.txt"))
        @test !any(endswith(".tmp"), readdir(folder))
    end
end

@testset "xxl sex study: book and xl keep the registry's fingerprint text" begin
    exp = find_experiment(load_registry(), "VI-1")
    out = mktempdir()
    book = read(joinpath(run_sex_world("book"; SS_KW..., out=out), "fingerprint.txt"), String)
    @test startswith(book, exp.fingerprint)
    xl = read(joinpath(run_sex_world("xl"; SS_KW..., out=out), "fingerprint.txt"), String)
    @test startswith(xl, exp.xl_fingerprint)
end

@testset "xxl sex study: a second call skips what is done, another fingerprint is refused" begin
    out = mktempdir()
    folder = run_sex_world("today"; SS_KW..., out=out)
    names = [ss_files(20)...; ss_files(21)...]
    before = [mtime(joinpath(folder, n)) for n in names]
    sleep(0.05)
    @test run_sex_world("today"; SS_KW..., out=out) == folder
    @test [mtime(joinpath(folder, n)) for n in names] == before

    write(joinpath(folder, "fingerprint.txt"), replace(read(joinpath(folder, "fingerprint.txt"), String), "periods=6" => "periods=7"))
    @test_throws ArgumentError run_sex_world("today"; SS_KW..., out=out)
end

@testset "xxl sex study: a seed cut short runs again, alone" begin
    out = mktempdir()
    folder = run_sex_world("xl"; SS_KW..., out=out)
    whole = read(joinpath(folder, "seed20.csv"))
    other = [mtime(joinpath(folder, n)) for n in ss_files(21)]
    rm(joinpath(folder, "seed20-sex.csv"))
    write(joinpath(folder, "seed20-agents.csv.tmp"), "half")
    sleep(0.05)
    run_sex_world("xl"; SS_KW..., out=out)
    @test read(joinpath(folder, "seed20.csv")) == whole
    @test isfile(joinpath(folder, "seed20-sex.csv"))
    @test !isfile(joinpath(folder, "seed20-agents.csv.tmp"))
    @test [mtime(joinpath(folder, n)) for n in ss_files(21)] == other
end

@testset "xxl sex study: the readings leave the standard CSV as a run without them" begin
    out = mktempdir()
    folder = run_sex_world("book"; seeds=1, first_seed=20, periods=6, io=devnull, out=out)
    exp = Sugarscape.with_steps(find_experiment(load_registry(), "VI-1"), 6)
    rows, _ = Sugarscape.timed_seed(exp, 20)
    plain = mktempdir()
    Sugarscape.write_seed_csv(joinpath(plain, "s.csv"), rows; columns=Sugarscape.metric_columns(exp.config))
    @test read(joinpath(folder, "seed20.csv")) == read(joinpath(plain, "s.csv"))
end

@testset "xxl sex study: the command line" begin
    a = sex_study_args(["--world", "xl", "--seeds", "3", "--first-seed", "4", "--periods", "50", "--jobs", "2", "--out", "o"])
    @test (a.world, a.seeds, a.first_seed, a.periods, a.jobs, a.out) == ("xl", 3, 4, 50, 2, "o")
    d = sex_study_args(["--world", "today"])
    @test (d.seeds, d.first_seed, d.periods, d.jobs, d.out) == (20, 80, 500, 1, RESULTS_XXL)
    for bad in (String[], ["--seeds", "3"], ["--world"], ["--world", "culture"], ["--world", "xl", "--seeds", "0"],
                ["--world", "xl", "--periods", "2"], ["--world", "xl", "--bogus"])
        @test_throws ArgumentError sex_study_args(bad)
    end
    quiet(f) = redirect_stderr(f, devnull)
    @test quiet(() -> sex_study_main(["--world", "culture"])) == 1
    @test quiet(() -> sex_study_main(String[])) == 1
    @test_throws ArgumentError run_sex_world("culture"; out=mktempdir(), io=devnull)
end

@testset "xxl sex study: a refused folder is a usage error, a finished run returns 0" begin
    out = mktempdir()
    args = ["--world", "today", "--seeds", "1", "--first-seed", "20", "--periods", "6", "--out", out]
    @test redirect_stdout(() -> sex_study_main(args), devnull) == 0
    @test isfile(joinpath(out, "sex-today-VI-1-s20-1-p6", "seed20-sex.csv"))
    fp = joinpath(out, "sex-today-VI-1-s20-1-p6", "fingerprint.txt")
    write(fp, replace(read(fp, String), "periods=6" => "periods=7"))
    @test redirect_stderr(() -> sex_study_main(args), devnull) == 1
end
