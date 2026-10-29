# Prints each XXL experiment's metrics against its base experiment's Julia xl run (docs/xxl.md, "Runner and experiments"):
#   julia --project=julia julia/xxl_report.jl [prefix] [--root DIR]
# For every XXL experiment whose id starts with `prefix` (all of them without one), it reads the seed CSVs of
# results-julia-xxl/<id> and of the base's results-julia-xl/<base>, and prints, per metric, the mean and the standard
# deviation across seeds at t = 50, 100, 200 and over the last 100 periods, xxl above xl, then the stepping seconds per
# period of both. It reads result folders only and runs nothing. `--root` names the directory holding the two result
# folders (default: the repository root). Standard library only, besides the package for its experiment table.
using Printf
using Sugarscape

const XXL_DIR = "results-julia-xxl"
const XL_DIR = "results-julia-xl"
const CHECKPOINTS = (50, 100, 200)  # single periods
const LAST_WINDOW = 100  # the last periods averaged for the final column
const COMMON = ["population", "mean_sugar", "gini"]  # every experiment
const TRADE = ["trades", "price_sd"]  # experiments with trade

"""A seed's table: `t` and the column names, and one `Vector{Float64}` of values per column, keyed by name."""
struct SeedTable
    t::Vector{Int}
    columns::Dict{String,Vector{Float64}}
end

# A CSV value as the Julia and Python runners write it: a float, "nan", "inf" or "-inf".
function parse_value(s::AbstractString)
    s = strip(s)
    s == "nan" && return NaN
    s == "inf" && return Inf
    s == "-inf" && return -Inf
    return parse(Float64, s)
end

# Reads a seed CSV by hand: a header line, then comma-separated rows.
function read_seed(path::AbstractString)
    lines = readlines(path)
    header = split(lines[1], ',')
    cols = [Float64[] for _ in header]
    for line in @view lines[2:end]
        isempty(strip(line)) && continue
        for (i, field) in enumerate(split(line, ','))
            push!(cols[i], parse_value(field))
        end
    end
    t = Int.(cols[1])
    return SeedTable(t, Dict(String(h) => c for (h, c) in zip(header, cols)))
end

# Every seed*.csv of a folder, in seed order.
function read_folder(dir::AbstractString)
    files = sort(
        filter(f -> occursin(r"^seed\d+\.csv$", f), readdir(dir));
        by=f -> parse(Int, match(r"\d+", f).match),
    )
    return [read_seed(joinpath(dir, f)) for f in files]
end

# One seed's value of a metric at period t, or the mean over the last LAST_WINDOW periods when t === :last. NaN where
# the period is missing or the metric has no finite value there.
function seed_value(tab::SeedTable, metric::AbstractString, t)
    haskey(tab.columns, metric) || return NaN
    col = tab.columns[metric]
    if t === :last
        last_t = maximum(tab.t)
        vals = [v for (tt, v) in zip(tab.t, col) if tt > last_t - LAST_WINDOW && isfinite(v)]
        return isempty(vals) ? NaN : sum(vals) / length(vals)
    end
    i = findfirst(==(t), tab.t)
    return i === nothing ? NaN : col[i]
end

"""The mean and sample standard deviation (n - 1) of the finite values, and how many there are."""
function mean_sd(vals)
    v = [x for x in vals if isfinite(x)]
    n = length(v)
    n == 0 && return (NaN, NaN, 0)
    mu = sum(v) / n
    n == 1 && return (mu, NaN, 1)
    return (mu, sqrt(sum((x - mu)^2 for x in v) / (n - 1)), n)
end

# "mean ± sd", with the count of seeds in brackets when some seeds had no value there.
function cell(tables, metric, t, nseeds)
    isempty(tables) && return "-"
    mu, sd, n = mean_sd([seed_value(tab, metric, t) for tab in tables])
    n == 0 && return "nan"
    text = isnan(sd) ? @sprintf("%.5g", mu) : @sprintf("%.5g ± %.3g", mu, sd)
    return n < nseeds ? text * " [$n]" : text
end

# Stepping seconds per period from a folder's timing.csv: (mean over seeds, min, max, mean start agents, mean end agents).
function stepping(dir::AbstractString)
    path = joinpath(dir, "timing.csv")
    isfile(path) || return nothing
    lines = readlines(path)
    header = split(lines[1], ',')
    rows = [split(l, ',') for l in lines[2:end] if !isempty(strip(l))]
    col(name) = [parse_value(r[findfirst(==(name), header)]) for r in rows]
    per = col("stepping_s") ./ col("periods")
    return (
        mean=sum(per) / length(per),
        lo=minimum(per),
        hi=maximum(per),
        start=sum(col("agents_start")) / length(rows),
        stop=sum(col("agents_end")) / length(rows),
    )
end

function timing_line(label, dir)
    s = stepping(dir)
    s === nothing && return @sprintf("  %-4s no timing.csv", label)
    return @sprintf(
        "  %-4s %.4g s per period stepping (seeds %.4g-%.4g), agents %.0f -> %.0f",
        label,
        s.mean,
        s.lo,
        s.hi,
        s.start,
        s.stop
    )
end

function fingerprint_status(dir, expected)
    path = joinpath(dir, "fingerprint.txt")
    isfile(path) || return "no fingerprint.txt"
    return read(path, String) == expected ? "fingerprint current" : "fingerprint STALE"
end

function report_experiment(root, reg, id, base_id, rules)
    xxl_dir = joinpath(root, XXL_DIR, replace(id, "/" => "_"))
    xl_dir = joinpath(root, XL_DIR, replace(base_id, "/" => "_"))
    if !isdir(xxl_dir)
        println("== $id: skipped, no $XXL_DIR/$(basename(xxl_dir)) yet\n")
        return false
    end
    exp, _ = Sugarscape.xxl_experiment(reg, id)
    xxl = read_folder(xxl_dir)
    xl = isdir(xl_dir) ? read_folder(xl_dir) : eltype(xxl)[]
    if isempty(xxl)
        println("== $id: skipped, $XXL_DIR/$(basename(xxl_dir)) holds no seed*.csv yet\n")
        return false
    end
    periods = maximum(xxl[1].t)
    println("== $id (base $base_id)  $(length(xxl)) xxl seeds, $(length(xl)) xl seeds, $periods periods")
    println("  rules: ", Sugarscape.rules_line(Sugarscape.to_xxl(exp.config, rules).xxl))
    println(
        "  xxl: ",
        fingerprint_status(xxl_dir, Sugarscape.xxl_fingerprint(exp, rules)),
        "; xl: ",
        isdir(xl_dir) ? fingerprint_status(xl_dir, "julia\n" * exp.xl_fingerprint) :
        "$xl_dir does not exist",
    )
    println(timing_line("xxl", xxl_dir))
    isdir(xl_dir) && println(timing_line("xl", xl_dir))
    println("  mean ± sd across seeds; [n] = seeds with a value, - = not collected")
    when = [CHECKPOINTS..., :last]
    heads = ["t=$t" for t in CHECKPOINTS]
    push!(heads, "last $LAST_WINDOW")
    @printf("  %-24s %-4s", "metric", "")
    for h in heads
        @printf(" %-24s", h)
    end
    println()
    xxl_only = [c for c in Sugarscape.XXL_METRIC_COLUMNS if haskey(xxl[1].columns, c)]
    metrics = vcat(COMMON, exp.config.trade ? TRADE : String[])
    for metric in metrics
        for (label, tables) in (("xxl", xxl), ("xl", xl))
            label == "xl" && isempty(tables) && continue
            @printf("  %-24s %-4s", label == "xxl" ? metric : "", label)
            for t in when
                @printf(" %-24s", cell(tables, metric, t, length(tables)))
            end
            println()
        end
    end
    for metric in xxl_only
        @printf("  %-24s %-4s", metric, "xxl")
        for t in when
            @printf(" %-24s", cell(xxl, metric, t, length(xxl)))
        end
        println()
    end
    println()
    return true
end

function main(args)
    root = dirname(@__DIR__)
    prefix = ""
    i = 1
    while i <= length(args)
        if args[i] == "--root"
            root = args[i + 1]
            i += 2
        else
            prefix = args[i]
            i += 1
        end
    end
    reg = load_registry()
    chosen = [e for e in Sugarscape.XXL_EXPERIMENTS if startswith(e[1], prefix)]
    if isempty(chosen)
        println(stderr, "no XXL experiment id starts with $(repr(prefix))")
        return 2
    end
    ran = 0
    for (id, base_id, rules) in chosen
        ran += report_experiment(root, reg, id, base_id, rules)
    end
    println("$ran of $(length(chosen)) XXL experiments reported")
    return 0
end

exit(main(ARGS))
