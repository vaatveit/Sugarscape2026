# xxl (stage 4): the disease list's report and command line (docs/superpowers/specs/2026-11-01-xxl-disease-list-design.md,
# "Screening"). Hand-made folders of run CSVs read into a report: the arms beside the baseline, the reading table and the
# choice, the readings and their ratios, what is read only past t = 500, an unfinished run, and the command line.
using Sugarscape, Test
isdefined(@__MODULE__, :list_folder) || include("disease_list_helpers.jl")

@testset "disease list report" begin
    dir = mktempdir()
    base = list_base(dir)
    base_name = "extinction-base-s20-20-p500"  # the folder list_base reads, which the command line takes the name from
    function arm(name; count=4, founder=2, lengths=(9, 10), kw...)
        folder = list_arm_folder(dir, "extinction-$name-s80-20-p500"; count, founder, lengths, lows=list_base_lows(), kw...)
        return Sugarscape.read_list_run(name, folder)
    end
    report(runs, b=base) = Sugarscape.disease_list_report(runs, b; label="t")
    armA, armB = arm("A"; count=6, band=18), arm("B"; count=4, band=20)

    @testset "a screening" begin
        r = report([armA, armB])
        @test occursin("| X10, per seed |", r) && occursin("Chosen: B", r)
        @test occursin("| A | 6 | 2 | (9, 10) |", r) && occursin("| B | 4 | 2 | (9, 10) |", r)
        @test occursin("| A | X10, per seed | 18 of 20 | at least 18 of 20 | pass |", r)
        @test occursin("| B | Extinction | 0 of 20 | none | pass |", r)
        @test occursin("Passing: A, B", r)
        # the Arms table names the folder each run was read from, the baseline's too
        @test occursin("| A | 6 | 2 | (9, 10) | 20 of 20 | 500 | extinction-A-s80-20-p500 |", r)
        @test occursin("| base (baseline) | 25 | 10 | (1, 10) | 20 of 20 | 500 | $base_name |", r)
        @test occursin("| Run | Diseases | Founder diseases | Lengths | Seeds | Periods | Folder |", r)
        @test !occursin("t = 1,501", r) && !occursin("Past t = 500", r)
        @test occursin("each side independently", r)
        @test !occursin("Unfinished", r) && !occursin("NaN", r)
        # the baseline's row comes first, in the settings and in the readings
        @test findfirst("| base (baseline) |", r).start < findfirst("| A | 6 |", r).start
        readings = split(r, "## Readings")[2]
        rows = [l for l in split(readings, "\n") if startswith(l, "| ")]
        @test startswith(rows[2], "| base | 20 | 5000.0 | 3000 |") && startswith(rows[3], "| A | 20 | 5000.0 | 3000 |")
        # the ratio of an arm's births to the baseline's, which are the same here
        @test occursin("| A | Births to t = 100 | 1 | [1, 1] | straddles |", r)
    end

    @testset "what the report reads" begin
        r = report([armA, armB])
        # the Choice says it is the screening table, which decides no confirmation or credit-off reading
        choice = split(split(r, "## Choice")[2], "## Readings")[1]
        @test occursin("This is the screening table, read at t ≤ 500. It does not decide a confirmation or credit-off reading.", choice)
        @test startswith(split(choice, "
")[3], "This is the screening table")
        @test occursin("This is the screening table", report(Sugarscape.ListRun[]))  # with no arm to choose
        # the t = 451–500 reading is named for its window, and births for theirs
        @test !occursin("End share sick", r)
        @test occursin("Share sick, t = 451–500", r) && occursin("| A | Share sick, t = 451–500 |", r)
        @test occursin("births t ≤ 100", r) && !occursin("births and X9 read t ≤ 500", r)
    end

    @testset "none passing" begin
        near = report([arm("Cnear"; band=17)])
        @test occursin("No arm passes.", near) && occursin("Near passing: Cnear (X10, per seed)", near)
        @test !occursin("Chosen", near) && occursin("| Cnear | X10, per seed | 17 of 20 | at least 18 of 20 | near |", near)
        far = report([arm("Dfar"; band=10)])
        @test occursin("No arm passes.", far) && occursin("No arm is near.", far) && !occursin("Near passing", far)
        @test occursin("| Dfar | X10, per seed | 10 of 20 | at least 18 of 20 | fail |", far)
        none = report(Sugarscape.ListRun[])
        @test occursin("No arm passes.", none) && occursin("No arm is near.", none)
    end

    @testset "past t = 500" begin
        # `inside` of the seeds with a share sick in the band at the end, `losing` with 3 diseases after t = 200 and 5 before
        function long_run(name, inside, losing; n=60, periods=2000)
            folder = list_folder(dir, "extinction-$name-s80-$n-p$periods";
                pops=[list_pop(i <= n ÷ 3 ? 3000.0 : 6000.0, 6000.0; periods) for i in 1:n],
                sick=[i <= inside ? 0.1 : 0.3 for i in 1:n],
                diseases=[i <= losing ? [t <= 200 ? 5.0 : 3.0 for t in 0:periods] : 5.0 for i in 1:n], periods)
            return Sugarscape.read_list_run(name, folder)
        end
        long, base_long = long_run("long", 54, 6), long_run("base_long", 40, 0)
        r = report([long], base_long)
        @test occursin("t = 501–1,000", r) && occursin("t = 1,501–2,000", r) && !occursin("t = 1,001", r)
        @test occursin("Seeds losing a disease after t = 200: 6 of 60", r)
        @test occursin("Seeds losing a disease after t = 200: 0 of 60", r)  # the baseline's
        @test occursin("Inside the band at the end: 54 of 60 (0.9 reached)", r)
        @test occursin("Inside the band at the end: 40 of 60 (0.9 not reached)", r)
        @test occursin("Share sick, t = 1,951–2,000: mean 0.12, 0 under, 54 inside, 6 over, 0 no value, of 60 seeds", r)
        # the past section says what its readings are, and which of them confirmation's per-seed X10 is
        past = split(r, "## Past t = 500")[2]
        @test occursin("No screening bar uses any of it", past) && occursin("per-seed X10", past) && occursin("confirmation", past)
        @test !occursin("End share sick", r) && !occursin("No bar uses", r)
        # each window past t = 500 shows the share sick over the window and the seeds inside the band
        wsick = split(split(r, "### t = 501–1,000")[2], "### t = 1,501")[1]
        wrows = [l for l in split(wsick, "
") if startswith(l, "| ")]
        @test occursin("| Share sick | Seeds in band |", wrows[1])
        @test endswith(wrows[2], "| 0.16667 | 40 of 60 |") && endswith(wrows[3], "| 0.12 | 54 of 60 |")  # base_long, long
        @test occursin("Diseases at t = 2,000: mean 4.8, sd 0.61, seeds by diseases 3: 6, 5: 54", r)
        @test occursin("Lowest population over t = 1–2,000: mean 5000.0, lowest 3000", r)
        @test occursin("| 3 | 6 | 0.1 |", r) && occursin("| 5 | 54 | 0.12222 |", r)  # the share sick by count
        # the baseline's row first in a window, its ratios after
        win = split(split(r, "### t = 501–1,000")[2], "### t = 1,501")[1]
        wrows = [l for l in split(win, "\n") if startswith(l, "| ")]
        @test startswith(wrows[2], "| base_long |") && startswith(wrows[3], "| long |")
        @test occursin("| long | Population | 1 | [1, 1] | straddles |", win)
        # a run that stops at t = 600 reaches neither window, but is past t = 500
        mid = long_run("mid", 8, 0; n=10, periods=600)
        mid_base = long_run("mid_base", 8, 0; n=10, periods=600)
        rm = report([mid], mid_base)
        @test occursin("Past t = 500", rm) && !occursin("t = 501–1,000", rm)
        @test occursin("Inside the band at the end: 8 of 10 (0.9 not reached)", rm)
        @test occursin("Share sick, t = 551–600: mean", rm)
        # a baseline that stops at 500 has no windows of its own, and the arms' say so
        rb = report([long], base)
        @test occursin("t = 501–1,000", rb) && occursin("$(base.name) stops at t = 500", rb)
        @test !occursin("| long | Population | 1 |", rb)
    end

    @testset "unfinished" begin
        # an arm with 19 whole seeds of 20, one cut short
        folder = list_arm_folder(dir, "extinction-short-s80-20-p500"; n=19, lows=list_base_lows()[1:19])
        write(joinpath(folder, "seed99.csv"), LIST_COLUMNS * "\n0,10000,1,0.1,5,0.3,40,0,1\n1,6000,2,0.1,5,0.3,40,0,1\n")
        short = Sugarscape.read_list_run("short", folder)
        r = report([short])
        @test occursin("**Unfinished: 1 of 20 seeds of short", r)
        @test occursin("No arm passes.", r) && occursin("No arm is near.", r) && occursin("| 19 of 20 | 500 |", r)
        @test occursin("| short | X9 | 19 of 19 | at least 18 of 19 | pass |", r)
        r2 = report([short, armB])
        @test occursin("Chosen: B", r2) && occursin("Not eligible, unfinished: short.", r2)
        # a baseline with seeds unfinished is flagged on the baseline's own account
        part = Sugarscape.read_list_run("part", list_arm_folder(dir, "extinction-part-s20-20-p500"; n=18, lows=list_base_lows()[1:18]))
        rp = report([armB], part)
        @test startswith(split(rp, "\n")[3], "**Unfinished: 2 of 20 seeds of the baseline part")
        @test occursin("Chosen: B", rp)
        @test !occursin("**Unfinished", report([armB]))
        # an arm with no finished seed doesn't stop the report, and is not screened
        empty_run = Sugarscape.read_list_run("empty", list_arm_folder(dir, "extinction-empty-s80-20-p500"; n=0))
        re = report([armA, empty_run, armB])
        @test occursin("**Unfinished: 20 of 20 seeds of empty", re) && occursin("Chosen: B", re)
        @test occursin("| empty | — | no finished seed | — | not screened |", re) && occursin("| 0 of 20 | 500 |", re)
        @test !occursin("NaN", re)
        @test occursin("No arm passes.", report([empty_run])) && occursin("No arm is near.", report([empty_run]))
    end

    @testset "the same world" begin
        world(name; fp=(;), kw...) = Sugarscape.read_list_run(name,
            list_arm_folder(dir, "extinction-$name-s80-20-p500"; lows=list_base_lows(), fingerprint=fp, kw...))
        diffs(run, b=base) = Sugarscape.world_differences(run, b)
        # the list, the code and the periods are not the world
        @test isempty(diffs(world("listonly"; count=4, founder=2, lengths=(9, 10))))
        @test isempty(diffs(world("code"; fp=(code="code-b",))))
        @test isempty(diffs(world("longer"; periods=600)))  # steps=500 stays on a longer run's fingerprint
        @test isempty(diffs(world("all3"; count=6, lengths=(1, 10), fp=(code="code-c",), periods=700)))
        @test isempty(diffs(base, base))
        # anything else is: credit off, the Config line, the maps, a rule on the xxl line
        @test diffs(world("off"; fp=(extra="credit options: credit off",))) == ["credit options: credit off"]
        cfg = diffs(world("cfg"; fp=(config=replace(LIST_CONFIG, "width=50" => "width=60"),)))
        @test length(cfg) == 1 && startswith(cfg[1], "Config(width=60,") && occursin("(the baseline has Config(width=50,", cfg[1])
        xl = diffs(world("xl"; fp=(xl_map="xl-b",)))
        @test xl == ["xl map sha256=xl-b (the baseline has xl map sha256=xl-a)"]
        xxl = diffs(world("xxl"; fp=(xxl_map="xxl-b",)))
        @test xxl == ["xxl map sugar-map-xxl.txt sha256=xxl-b (the baseline has xxl map sugar-map-xxl.txt sha256=xxl-a)"]
        both = diffs(world("both"; fp=(extra="credit options: credit off", xl_map="xl-b")))
        @test length(both) == 2
        # a baseline that is credit off differs from an arm that isn't
        off = world("off2"; fp=(extra="credit options: credit off",))
        @test diffs(base, off) == ["the baseline has credit options: credit off"]
        # a rule on the xxl line differs even beside the list's own settings, which are left out of the comparison
        rule = Sugarscape.read_list_run("rule", list_folder(dir, "extinction-rule-s80-20-p500";
            pops=[list_pop(5000.0, 6000.0) for _ in 1:20], sick=fill(0.1, 20), diseases=fill(5.0, 20),
            settings="travel_cost=0.5 disease_count=4 founder_diseases=2 disease_lengths=(9, 10)"))
        @test length(diffs(rule)) == 1 && startswith(diffs(rule)[1], "xxl vision_shape=\"disc\"")
        @test occursin("travel_cost=0.5", diffs(rule)[1])
        # a CRLF fingerprint is the same world as an LF one
        world("crlf")
        path = joinpath(dir, "extinction-crlf-s80-20-p500", "fingerprint.txt")
        write(path, replace(read(path, String), "\n" => "\r\n"))
        @test isempty(diffs(Sugarscape.read_list_run("crlf", dirname(path))))

        # the report: a bold line per difference, per arm, at the top; nothing when there is none
        @test !occursin("isn't the baseline's world", report([armA, armB]))
        r = report([off])
        @test startswith(split(r, "\n")[3], "**off2 isn't the baseline's world: credit options: credit off**")
        @test occursin("Chosen: off2", r)  # it doesn't change the choice
        r2 = report([world("off3"; fp=(extra="credit options: credit off", xl_map="xl-b")), armB])
        @test count("**off3 isn't the baseline's world: ", r2) == 2 && !occursin("B isn't the baseline's world", r2)
        # arms that ran on different code get one line naming them; the baseline's code is not compared
        @test !occursin("different code", report([armA, armB]))
        @test !occursin("different code", report([world("onlyb"; fp=(code="code-b",))]))
        c = report([armA, world("cb"; fp=(code="code-b",)), armB, world("cb2"; fp=(code="code-b",))])
        @test count("different code", c) == 1
        @test occursin("**The arms ran on different code: A, B on code-a; cb, cb2 on code-b.**", c)
        @test !occursin("isn't the baseline's world", c)
    end

    @testset "an extinct seed in the report" begin
        # 20 seeds over 600 periods: seed 80 dies at t = 480 and seed 81 at t = 550, and the share sick, Gini, sugar and
        # price have no value once they are dead.
        dies(at, alive, dead) = vcat(fill(alive, at), fill(dead, 601 - at))
        pops = [i == 1 ? vcat(10000.0, fill(6000.0, 479), zeros(121)) : i == 2 ? vcat(10000.0, fill(6000.0, 549), zeros(51)) :
                list_pop(list_base_lows()[i], 6000.0; periods=600) for i in 1:20]
        at(i) = i == 1 ? 480 : i == 2 ? 550 : 601
        gone = Sugarscape.read_list_run("gone", list_folder(dir, "extinction-gone-s80-20-p600";
            pops, sick=[dies(at(i), 0.1, NaN) for i in 1:20], diseases=[dies(at(i), 5.0, 0.0) for i in 1:20], periods=600,
            gini=i -> dies(at(i), 0.3, NaN), sugar=i -> dies(at(i), 40.0, NaN), price=i -> dies(at(i), 1.0, NaN),
            trades=i -> dies(at(i), 0.0, 0.0)))
        r = report([gone])
        @test !occursin("NaN", r)
        # t = 451–500 (the first has no value; the second was alive) and the last 50 periods (neither has)
        @test occursin("| gone | 0.1 | 0 | 19 | 0 | 1 |", r)
        @test occursin("Share sick, t = 551–600: mean 0.1, 0 under, 18 inside, 0 over, 2 no value, of 20 seeds", r)
        @test occursin("Inside the band at the end: 18 of 20 (0.9 reached)", r)
        @test occursin("Diseases at t = 600: mean 4.5, sd 1.54, seeds by diseases 0: 2, 5: 18", r)
        @test occursin("| 0 | 2 | — |", r) && occursin("| 5 | 18 | 0.1 |", r)  # the dead seeds' share sick has no value
        @test occursin("| gone | Extinction | 2 of 20 | none | fail |", r)
        @test occursin("| gone | X10, per seed | 19 of 20 | at least 18 of 20 | pass |", r)
        # the counts of the t = 451–500 table and the past section add up to the seeds
        m = match(r"\| gone \| 0\.1 \| (\d+) \| (\d+) \| (\d+) \| (\d+) \|", r)
        @test sum(parse.(Int, m.captures)) == 20
        p = match(r"mean 0\.1, (\d+) under, (\d+) inside, (\d+) over, (\d+) no value, of 20 seeds", r)
        @test sum(parse.(Int, p.captures)) == 20
    end

    @testset "the diseases circulating, by period" begin
        # four seeds with different numbers of diseases at t = 100, 200 and 500 (and 1 elsewhere); the baseline's are 5
        circ(a, b, c) = [Float64[t == 100 ? a[i] : t == 200 ? b[i] : t == 500 ? c[i] : 1.0 for t in 0:500] for i in 1:4]
        circ_run(name, d) = Sugarscape.read_list_run(name, list_folder(dir, "extinction-$name-s1-4-p500";
            pops=[list_pop(6000.0, 6000.0) for _ in 1:4], sick=fill(0.1, 4), diseases=d))
        arm_c = circ_run("circ", circ([1, 1, 3, 3], [2, 2, 2, 5], [0, 4, 4, 4]))
        base_c = circ_run("circbase", fill(5.0, 4))
        r = report([arm_c], base_c)
        section = split(split(r, "Diseases circulating, by the number of diseases: seeds.")[2], "Share sick over")[1]
        rows = [l for l in split(section, "\n") if startswith(l, "| ")][2:end]  # past the header
        @test rows == [
            "| circbase | t = 100 | 5.0 | 0.0 | 5: 4 |", "| circ | t = 100 | 2.0 | 1.15 | 1: 2, 3: 2 |",
            "| circbase | t = 200 | 5.0 | 0.0 | 5: 4 |", "| circ | t = 200 | 2.75 | 1.5 | 2: 3, 5: 1 |",
            "| circbase | t = 500 | 5.0 | 0.0 | 5: 4 |", "| circ | t = 500 | 3.0 | 2.0 | 0: 1, 4: 3 |",
        ]
    end

    @testset "runs it can't read" begin
        stub = Sugarscape.read_list_run("stub", list_arm_folder(dir, "extinction-stub-s80-20-p100"; periods=100))
        @test_throws ArgumentError report([stub])
        @test_throws ArgumentError report([armA], stub)
        no_seeds = Sugarscape.read_list_run("none", list_arm_folder(dir, "extinction-none-s20-20-p500"; n=0))
        @test_throws ArgumentError report([armA], no_seeds)
    end

    @testset "the command line" begin
        usage(args) = redirect_stderr(() -> Sugarscape.disease_list_main(args), devnull)
        out = mktempdir()
        @test usage(["--out", out]) == 2                                  # no --base
        @test usage(["--base", "b", "--out", out]) == 2                   # no --arms
        @test usage(["--base", "b", "--arms", "A", "--out", out]) == 2    # no = in an arm
        @test usage(["--base", "missing", "--arms", "A=missing", "--out", out]) == 2
        @test usage(["--nope"]) == 2
        # arguments
        a = Sugarscape.disease_list_args(["--base", "b", "--arms", "A=fa,B=fb", "--out", "o", "--label", "x"])
        @test a == (base="b", arms=["A" => "fa", "B" => "fb"], out="o", label="x")
        d = Sugarscape.disease_list_args(["--base", "b", "--arms", "A=f=g"])
        @test d.out == Sugarscape.RESULTS_XXL && d.label == "screening" && d.arms == ["A" => "f=g"]
        @test_throws ArgumentError Sugarscape.disease_list_args(["--base", "b", "--arms", "A=f,A=g"])      # a name twice
        @test_throws ArgumentError Sugarscape.disease_list_args(["--base", "b", "--arms", "=f"])
        @test_throws ArgumentError Sugarscape.disease_list_args(["--base", "b", "--arms", "A="])
        @test_throws ArgumentError Sugarscape.disease_list_args(["--base", "b", "--arms", "A=f", "--label", "a/b"])
        @test_throws ArgumentError Sugarscape.disease_list_args(["--base", "b", "--arms"])
        # a folder that stops short of t = 500, a baseline with no seed, and a folder that holds none of a run
        list_arm_folder(dir, "extinction-p100-s80-20-p100"; periods=100)
        list_arm_folder(dir, "extinction-empty-s20-20-p500"; n=0)
        mkpath(joinpath(dir, "not-a-run"))
        @test usage(["--base", base_name, "--arms", "A=extinction-p100-s80-20-p100", "--out", dir]) == 2
        @test usage(["--base", "extinction-empty-s20-20-p500", "--arms", "A=extinction-A-s80-20-p500", "--out", dir]) == 2
        @test usage(["--base", "not-a-run", "--arms", "A=extinction-A-s80-20-p500", "--out", dir]) == 2
        # a real pair of folders
        args = ["--base", base_name, "--arms", "A=extinction-A-s80-20-p500,B=extinction-B-s80-20-p500",
                "--out", dir, "--label", "t"]
        code, printed = mktemp() do path, io
            code = redirect_stdout(() -> Sugarscape.disease_list_main(args), io)
            flush(io)
            return code, read(path, String)
        end
        file = joinpath(dir, "disease-list-t.md")
        @test code == 0 && isfile(file)
        written = read(file, String)
        @test printed == written * "-> " * file * "\n"
        @test occursin("Chosen: B", written) && occursin("| A | 6 | 2 | (9, 10) |", written)
        @test occursin("(baseline)", written) && occursin(base_name, written)
        @test !isfile(file * ".tmp")
    end
end
