# xxl: the loan trace's run and command line (docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md, "The
# runs"). Short runs of VI-1 into temporary folders, as the extinction test does: the worlds, the files, the resume, the
# refusals, the report, the comparison and the command line.
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")
using Sugarscape, Test
using Sugarscape:
    TraceWorld,
    trace_rules,
    trace_xl,
    trace_experiment,
    trace_config,
    trace_term,
    trace_fingerprint,
    loan_name,
    trace_seed_done,
    loan_trace_seed!,
    run_loan_trace,
    rebuild_loan_report,
    loan_compare,
    loan_trace_main,
    read_census,
    read_tally,
    age_ratios,
    read_seed_csv,
    credit_off_reading,
    source_sha256,
    run_extinction,
    extinction_name,
    fmt

const LRUN_VI1 = find_experiment(load_registry(), "VI-1")
const LRUN_DEFAULTS = TraceWorld("defaults", (10, 10.0), false)

# VI-1 with some config fields replaced, as the extinction test's `ext_exp` does for its worlds.
function lrun_exp(; kw...)
    e = LRUN_VI1
    return Experiment(
        e.id, e.title, e.rules, e.steps, e.seeds, replace_config(e.config; kw...), e.fingerprint, e.xl_config,
        e.xl_fingerprint,
    )
end

# Two seeds from 5 over 12 periods, in this process, quietly.
function lrun_go(w, out; label="t", seeds=2, first_seed=5, periods=12, kw...)
    return run_loan_trace(w; label=label, seeds=seeds, first_seed=first_seed, periods=periods, jobs=1, out=out,
                          io=devnull, kw...)
end
lrun_dir(out; label="t", first=5, seeds=2, periods=12) = joinpath(out, loan_name(label, first, seeds, periods))
lrun_report(out; kw...) = read(lrun_dir(out; kw...) * ".md", String)
function lrun_files(folder, k)
    return [joinpath(folder, "seed$k.$kind") for kind in ("csv", "timing.csv", "tally.csv", "census.csv", "loans.csv")]
end
lrun_usage(args) = redirect_stderr(() -> loan_trace_main(args), devnull)

@testset "loan run: worlds" begin
    for name in ("defaults", "xl", "book"), inheritance in (false, true)
        w = TraceWorld(name, (5, 10.0), inheritance)
        cfg = trace_config(w, trace_experiment(w, 12))
        @test cfg.credit == (5, 10.0) && cfg.inheritance == inheritance
        off = TraceWorld(name, nothing, inheritance)
        @test trace_config(off, trace_experiment(off, 12)).credit === nothing
    end
    cfg(name) = (w = TraceWorld(name, (5, 10.0), false); trace_config(w, trace_experiment(w, 12)))
    @test cfg("defaults").xxl !== nothing && cfg("xl").xxl === nothing && cfg("book").xxl === nothing
    @test cfg("book").width == 50 && cfg("xl").width == 500 && cfg("defaults").width == 500  # xxl runs at xl size
    @test trace_rules(TraceWorld("defaults", nothing, false)) === XXL_DEFAULTS
    @test trace_rules(TraceWorld("xl", nothing, false)) === nothing
    @test trace_rules(TraceWorld("book", nothing, false)) === nothing
    @test trace_xl(TraceWorld("xl", nothing, false)) && !trace_xl(TraceWorld("book", nothing, false))
    @test_throws ArgumentError TraceWorld("x", nothing, false)
    # The term the report adjusts by is the one the seeds run: 10 with credit off, as the census follow-up needs one.
    for name in ("defaults", "xl", "book")
        w = TraceWorld(name, (5, 10.0), false)
        @test trace_term(w) == 5 == first(trace_config(w, trace_experiment(w, 12)).credit)
        @test trace_term(TraceWorld(name, nothing, false)) == 10
    end
    exp = trace_experiment(LRUN_DEFAULTS, 12)
    @test exp.steps == 12 && exp.id == "VI-1"
    @test loan_name("defaults", 20, 10, 2000) == "loans-defaults-s20-10-p2000"
end

@testset "loan run: the fingerprint" begin
    lines(w, periods=12) = split(trace_fingerprint(trace_experiment(w, periods), w, periods), "\n")
    d = lines(LRUN_DEFAULTS)
    @test "world=defaults" in d && "credit=(10, 10.0)" in d && "inheritance=false" in d && "periods=12" in d
    @test "code sha256=$(source_sha256(dirname(pathof(Sugarscape))))" in d
    @test startswith(trace_fingerprint(trace_experiment(LRUN_DEFAULTS, 12), LRUN_DEFAULTS, 12),
                     Sugarscape.xxl_fingerprint(trace_experiment(LRUN_DEFAULTS, 12), XXL_DEFAULTS))
    xl = TraceWorld("xl", nothing, true)
    @test startswith(trace_fingerprint(trace_experiment(xl, 12), xl, 12), "julia\nlook: centred\n")
    @test "credit=nothing" in lines(xl) && "inheritance=true" in lines(xl)
    book = TraceWorld("book", (10, 10.0), false)
    @test startswith(trace_fingerprint(trace_experiment(book, 12), book, 12), "julia\n(")
    @test length(unique([lines(w) for w in (LRUN_DEFAULTS, xl, book, TraceWorld("defaults", (5, 10.0), false))])) == 4
end

@testset "loan run: a run writes its files" begin
    out = mktempdir()
    s = lrun_go(LRUN_DEFAULTS, out)
    folder = lrun_dir(out)
    @test sort(readdir(folder)) == sort([
        "elapsed.txt", "fingerprint.txt", "machine.txt",
        (basename(f) for k in (5, 6) for f in lrun_files(folder, k))...,
    ])
    @test all(k -> trace_seed_done(folder, k, 12), (5, 6)) && !trace_seed_done(folder, 7, 12)
    @test !trace_seed_done(folder, 5, 13)
    @test s.seeds == [5, 6] && s.started > 0
    report = lrun_report(out)
    @test occursin("- Seeds finished: 2 of 2", report) && occursin("# Loan trace: t", report)
    @test occursin("- World: defaults, credit term 10, rate 10.0, inheritance false", report)
    @test !occursin("NaN", report)
    @test !any(f -> endswith(f, ".tmp"), readdir(folder))
    # The book's world and the xl's rules-free path have no xxl columns; inheritance runs as well.
    for (inheritance, label) in ((false, "book"), (true, "inh"))
        lrun_go(TraceWorld("book", (10, 10.0), inheritance), out; label=label, seeds=1)
        f = lrun_dir(out; label=label, seeds=1)
        @test trace_seed_done(f, 5, 12)
        @test split(readline(joinpath(f, "seed5.csv")), ",") == ["t"; Sugarscape.METRIC_COLUMNS]
    end
end

@testset "loan run: a traced seed is the extinction run's" begin
    one, two = mktempdir(), mktempdir()
    lrun_go(LRUN_DEFAULTS, one)
    run_extinction(XXL_DEFAULTS; label="t", seeds=2, first_seed=5, periods=12, jobs=1, out=two, io=devnull)
    ext = joinpath(two, extinction_name("t", 5, 2, 12))
    for k in (5, 6)
        @test read(joinpath(lrun_dir(one), "seed$k.csv")) == read(joinpath(ext, "seed$k.csv"))
    end
end

@testset "loan run: a seed stopped part-way runs again" begin
    out = mktempdir()
    lrun_go(LRUN_DEFAULTS, out)
    folder = lrun_dir(out)
    seed(k) = Dict(f => read(f) for f in lrun_files(folder, k) if !endswith(f, "timing.csv"))  # timings differ per run
    whole, other_time = seed(6), mtime(joinpath(folder, "seed5.csv"))
    rm(joinpath(folder, "seed6.tally.csv"))
    @test !trace_seed_done(folder, 6, 12)
    lrun_go(LRUN_DEFAULTS, out)
    @test seed(6) == whole && trace_seed_done(folder, 6, 12)
    @test mtime(joinpath(folder, "seed5.csv")) == other_time
    # The CSV cut short, with a stray temporary file and the loans file gone as well.
    path = joinpath(folder, "seed6.csv")
    write(path, join(readlines(path)[1:3], "\n") * "\n")
    write(path * ".tmp", "stray")
    rm(joinpath(folder, "seed6.loans.csv"))
    lrun_go(LRUN_DEFAULTS, out)
    @test seed(6) == whole && !isfile(path * ".tmp")
    @test mtime(joinpath(folder, "seed5.csv")) == other_time
    # The trace files whole but the CSV never written: not done either.
    rm(path)
    @test !trace_seed_done(folder, 6, 12)
    lrun_go(LRUN_DEFAULTS, out)
    @test seed(6) == whole
end

@testset "loan run: a CSV is written last" begin
    exp, folder = trace_experiment(LRUN_DEFAULTS, 12), mktempdir()
    stopped(args...) = error("stopped")
    @test_throws ErrorException loan_trace_seed!(exp, 5, LRUN_DEFAULTS, folder; write_files=stopped)
    @test !isfile(joinpath(folder, "seed5.csv")) && !trace_seed_done(folder, 5, 12)
    # Trace files written, then a stop before the CSV: still not done.
    wrote_then_stopped(f, k, tr) = (Sugarscape.write_trace_files(f, k, tr); error("stopped"))
    @test_throws ErrorException loan_trace_seed!(exp, 5, LRUN_DEFAULTS, folder; write_files=wrote_then_stopped)
    @test isfile(joinpath(folder, "seed5.tally.csv")) && !isfile(joinpath(folder, "seed5.csv"))
    @test !trace_seed_done(folder, 5, 12)
    seconds = loan_trace_seed!(exp, 5, LRUN_DEFAULTS, folder)
    @test seconds > 0 && trace_seed_done(folder, 5, 12) && !isfile(joinpath(folder, "seed5.csv.tmp"))
end

@testset "loan run: other settings are refused" begin
    out = mktempdir()
    lrun_go(LRUN_DEFAULTS, out)
    folder = lrun_dir(out)
    # The fingerprint is rewritten below, so its time is left out.
    snapshot() = [(f, mtime(f)) for f in sort(readdir(folder; join=true)) if !endswith(f, "fingerprint.txt")]
    before = snapshot()
    for w in (TraceWorld("defaults", (5, 10.0), false), TraceWorld("defaults", nothing, false),
              TraceWorld("defaults", (10, 10.0), true), TraceWorld("book", (10, 10.0), false))
        @test_throws ArgumentError lrun_go(w, out)
        @test_throws ArgumentError rebuild_loan_report(
            w; label="t", seeds=2, first_seed=5, periods=12, out=out, io=devnull
        )
    end
    fp = joinpath(folder, "fingerprint.txt")
    original = read(fp, String)
    write(fp, replace(original, "periods=12" => "periods=13"))
    @test_throws ArgumentError lrun_go(LRUN_DEFAULTS, out)
    write(fp, original)
    @test snapshot() == before
    # The same refusals as usage errors on the command line.
    args = ["--label", "t", "--seeds", "2", "--first-seed", "5", "--periods", "12", "--out", out]
    @test lrun_usage([args..., "--term", "5"]) == 2
    @test lrun_usage([args..., "--world", "book"]) == 2
    @test lrun_usage([args; "--no-credit"]) == 2
    @test lrun_usage([args; "--inheritance"]) == 2
    @test snapshot() == before
end

@testset "loan run: the report can be rebuilt" begin
    out = mktempdir()
    lrun_go(LRUN_DEFAULTS, out)
    md = lrun_dir(out) * ".md"
    kw = (label="t", seeds=2, first_seed=5, periods=12, out=out, io=devnull)
    body(text) = filter(l -> !startswith(l, "- Run time"), split(text, "\n"))
    text = read(md, String)
    rm(md)
    s = rebuild_loan_report(LRUN_DEFAULTS; kw...)
    @test s.seeds == [5, 6] && body(read(md, String)) == body(text)
    @test occursin("- Run time: ", read(md, String))
    @test_throws ArgumentError rebuild_loan_report(LRUN_DEFAULTS; kw..., out=mktempdir())
    # Edited code is a warning, not a refusal.
    fp = joinpath(lrun_dir(out), "fingerprint.txt")
    original = read(fp, String)
    write(fp, replace(original, r"code sha256=[0-9a-f]+" => "code sha256=edited"))
    said = IOBuffer()
    rm(md)
    rebuild_loan_report(LRUN_DEFAULTS; kw..., io=said)
    @test occursin("warning: the code differs", String(take!(said))) && body(read(md, String)) == body(text)
    write(fp, original)
    # A seed missing its trace files is left out of the report.
    rm(joinpath(lrun_dir(out), "seed6.census.csv"))
    rebuild_loan_report(LRUN_DEFAULTS; kw...)
    @test occursin("- Seeds finished: 1 of 2", read(md, String))
end

@testset "loan run: two workers give the same seeds" begin
    one, two = mktempdir(), mktempdir()
    lrun_go(LRUN_DEFAULTS, one)
    run_loan_trace(LRUN_DEFAULTS; label="t", seeds=2, first_seed=5, periods=12, jobs=2, out=two, io=devnull)
    for k in (5, 6), kind in ("csv", "tally.csv", "census.csv", "loans.csv")
        a, b = lrun_dir(one), lrun_dir(two)
        @test read(joinpath(a, "seed$k.$kind")) == read(joinpath(b, "seed$k.$kind"))
    end
    @test occursin("- Seeds finished: 2 of 2", lrun_report(two))
end

@testset "loan run: no credit runs" begin
    out = mktempdir()
    w = TraceWorld("defaults", nothing, false)
    # 70 periods: the census of t = 50 is followed for 11 more, so it is whole by the end.
    s = lrun_go(w, out; periods=70)
    folder = lrun_dir(out; periods=70)
    report = lrun_report(out; periods=70)
    @test s.seeds == [5, 6] && s.started == 0
    @test occursin("- Seeds finished: 2 of 2", report) && occursin("- X8, t = 1–500: —", report)
    @test !occursin("NaN", report)
    census = read_census(joinpath(folder, "seed5.census.csv"))
    @test !isempty(census) && sum(r.n for r in census if r.group == "all") > 0
    @test occursin("credit=nothing", read(joinpath(folder, "fingerprint.txt"), String))
end

@testset "loan run: an extinct world" begin
    out = mktempdir()
    doomed = lrun_exp(; max_age=(2, 2))  # all dead of old age within a few periods
    s = lrun_go(LRUN_DEFAULTS, out; seeds=1, periods=10, experiment=doomed)
    report = lrun_report(out; seeds=1, periods=10)
    @test s.seeds == [5] && !occursin("NaN", report)
    header, M = read_seed_csv(joinpath(lrun_dir(out; seeds=1, periods=10), "seed5.csv"))
    @test M[end, findfirst(==("population"), header)] == 0
    @test occursin("# Loan trace: t", report)
end

@testset "loan run: the report adjusts by the world's term" begin
    out = mktempdir()
    # 70 periods: the census of t = 50 is whole by the end, so the age ratios can be read.
    w = TraceWorld("defaults", (5, 10.0), false)
    s = lrun_go(w, out; label="five", seeds=1, periods=70)
    folder = lrun_dir(out; label="five", seeds=1, periods=70)
    t = read_tally(joinpath(folder, "seed5.tally.csv"))
    census = read_census(joinpath(folder, "seed5.census.csv"))
    five, ten = age_ratios(t, census, [1]; term=5), age_ratios(t, census, [1]; term=10)
    @test !isnan(five.lender) && !isnan(five.borrower)
    @test five.borrower != ten.borrower
    @test isequal(s.check.age, five)
    report = read(folder * ".md", String)
    @test occursin("5/6", report) && occursin("| Age ratio, borrowers: all | $(fmt(five.borrower)) |", report)
    kw = (label="five", seeds=1, first_seed=5, periods=70, out=out, io=devnull)
    @test isequal(rebuild_loan_report(w; kw...).check.age, five)
    # A comparison takes each folder's own term from its fingerprint.
    name = loan_name("five", 5, 1, 70)
    text = loan_compare(out, name, String[]; periods=70)
    row = split(only(filter(l -> startswith(l, "| $name "), split(text, "\n"))), " | ")
    @test row[4] == fmt(five.borrower) && row[5] == fmt(five.lender)
    @test Sugarscape.compare_folder(out, name).term == 5
    lrun_go(TraceWorld("defaults", nothing, false), out; label="off", seeds=1)
    @test Sugarscape.compare_folder(out, loan_name("off", 5, 1, 12)).term == 10
end

# A hand reading of a folder's seeds: mean births, trough and end population over `seeds`, cut to `periods`.
function lrun_read(out, name, seeds, periods)
    births, trough, ends = Float64[], Float64[], Float64[]
    for k in seeds
        header, M = read_seed_csv(joinpath(out, name, "seed$k.csv"))
        pop, ever = (findfirst(==(c), header) for c in ("population", "agents_ever"))
        push!(births, M[periods + 1, ever] - M[1, ever])
        push!(trough, minimum(M[2:(periods + 1), pop]))
        push!(ends, M[periods + 1, pop])
    end
    mean(v) = sum(v) / length(v)
    return (; births=mean(births), trough=mean(trough), population=mean(ends))
end

@testset "loan run: the comparison" begin
    out = mktempdir()
    lrun_go(LRUN_DEFAULTS, out; label="base", seeds=3, first_seed=5)
    lrun_go(TraceWorld("defaults", nothing, false), out; label="off", seeds=2, first_seed=6)
    base, off = loan_name("base", 5, 3, 12), loan_name("off", 6, 2, 12)
    text = loan_compare(out, base, [off]; periods=8)
    @test read(joinpath(out, "loans-compare.md"), String) == text
    @test occursin("- Seeds: 6, 7 (2 in all)", text) && occursin("- Periods: 8", text)
    row(name) = split(only(filter(l -> startswith(l, "| $name "), split(text, "\n"))), " | ")
    columns = split(only(filter(l -> startswith(l, "| Run "), split(text, "\n"))), " | ")
    @test columns[end - 2:end] == ["Births", "Trough", "End population |"]
    base_read, off_read = lrun_read(out, base, 6:7, 8), lrun_read(out, off, 6:7, 8)
    for (name, x) in ((base, base_read), (off, off_read))
        r = row(name)
        @test r[end - 2] == fmt(x.births) && r[end - 1] == fmt(x.trough) && r[end] == fmt(x.population) * " |"
    end
    @test row(off)[2] == "—" && row(off)[3] == "0" && row(off)[4] == "—"  # no credit: nothing to divide by
    @test !occursin("NaN", text)
    reading = credit_off_reading(base_read, off_read)
    @test (reading !== nothing) == occursin("With credit off", text)
    reading === nothing || @test occursin("- $off: $reading", text)
    # Alone, and on the shared seeds only.
    @test occursin("(3 in all)", loan_compare(out, base, String[]; periods=12))
    # Refused: a folder with fewer periods than asked, an absent folder, nothing in common.
    @test_throws ArgumentError loan_compare(out, base, [off]; periods=13)
    @test_throws ArgumentError loan_compare(out, base, ["loans-nope-s5-2-p12"]; periods=8)
    @test_throws ArgumentError loan_compare(out, base, ["fingerprint"]; periods=8)
    lrun_go(LRUN_DEFAULTS, out; label="far", seeds=1, first_seed=40)
    @test_throws ArgumentError loan_compare(out, base, [loan_name("far", 40, 1, 12)]; periods=8)
end

@testset "loan run: the comparison cuts a longer run to the periods" begin
    out = mktempdir()
    lrun_go(LRUN_DEFAULTS, out; label="long", seeds=1, periods=20)
    lrun_go(LRUN_DEFAULTS, out; label="short", seeds=1, periods=12)
    long, short = loan_name("long", 5, 1, 20), loan_name("short", 5, 1, 12)
    text = loan_compare(out, long, [short]; periods=12)
    # The same seed, so the same CSV for the first 12 periods: the CSV figures agree. The loan figures are by whole
    # window, so the longer run's differ, as it began more loans.
    rows = [split(l, " | ") for l in split(text, "\n") if startswith(l, "| loans-")]
    @test length(rows) == 2 && rows[1][(end - 2):end] == rows[2][(end - 2):end]
    @test rows[1][end] == fmt(lrun_read(out, long, 5:5, 12).population) * " |"
end

@testset "loan run: the command line" begin
    for args in (
        ["--seeds", "0"], ["--jobs", "0"], ["--periods", "3"], ["--first-seed", "-1"], ["--nope"], ["--world", "x"],
        ["--term", "0"], ["--term", "5", "--no-credit"], ["--term", "49"], ["--seeds"], ["--seeds", "many"],
        ["--report-only", "--out", mktempdir()], ["--compare", "a,,b", "--out", mktempdir()],
        ["--compare", "loans-a-s1-1-p5", "--out", mktempdir()],
    )
        @test lrun_usage(args) == 2
    end
end

@testset "loan run: the xl world from the command line" begin
    out = mktempdir()
    args = ["--world", "xl", "--seeds", "2", "--first-seed", "5", "--periods", "12", "--jobs", "1", "--out", out]
    @test redirect_stdout(() -> loan_trace_main(args), devnull) == 0
    folder = lrun_dir(out; label="xl")
    for k in (5, 6)
        @test isfile(joinpath(folder, "seed$k.tally.csv")) && isfile(joinpath(folder, "seed$k.census.csv"))
        @test trace_seed_done(folder, k, 12)
    end
    @test occursin("- World: xl, credit term 10, rate 10.0, inheritance false", read(folder * ".md", String))
end

@testset "loan run: a successful main" begin
    out = mktempdir()
    args = ["--seeds", "1", "--first-seed", "5", "--periods", "4", "--jobs", "1", "--out", out]
    @test redirect_stdout(() -> loan_trace_main(args), devnull) == 0  # --label defaults to the world's name
    folder = lrun_dir(out; label="defaults", first=5, seeds=1, periods=4)
    @test trace_seed_done(folder, 5, 4) && occursin("- Seeds finished: 1 of 1", read(folder * ".md", String))
    rm(folder * ".md")
    @test redirect_stdout(() -> loan_trace_main([args; "--report-only"]), devnull) == 0
    @test isfile(folder * ".md")
    compare = ["--compare", basename(folder), "--periods", "4", "--out", out]
    @test redirect_stdout(() -> loan_trace_main(compare), devnull) == 0
    @test occursin(basename(folder), read(joinpath(out, "loans-compare.md"), String))
    # Another term goes to a folder of its own only by label, so the same label is refused.
    @test lrun_usage([args..., "--term", "5"]) == 2
end
