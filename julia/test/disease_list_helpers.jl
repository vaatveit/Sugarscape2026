# Helpers for the disease list's readings: hand-made folders of run CSVs. No test_ prefix, so the runner doesn't run it;
# a test file includes it under an isdefined guard, as it does helpers.jl.
using Sugarscape

const LIST_COLUMNS = "t,population,agents_ever,fraction_sick,diseases_circulating,gini,mean_sugar,trades,mean_price"

# One seed's column: a vector as it is (one value a period, t = 0 to periods), a number held throughout.
list_column(x::AbstractVector, periods) = Float64.(x)
list_column(x::Real, periods) = fill(Float64(x), periods + 1)

"""
A folder of seeds' CSVs under `dir/name` for the disease list's readings: `pops`, `sick` and `diseases` hold one entry
per seed, a number held throughout or a vector with a value for each period t = 0 to `periods`. They fill the columns
population, fraction_sick and diseases_circulating. `ever`, `gini`, `sugar`, `trades` and `price` fill the other
columns, each a number or vector for every seed, or a function of the seed's place (1, 2, ...) giving one. The first
seed is the one the name gives (`-s80-20-p500`: 80), else 1. The fingerprint has an `xxl` line with `settings` at its end,
a `Config` line for the book's list, and the periods.
"""
function list_folder(dir, name; pops, sick, diseases, settings="", periods=500,
                     ever=nothing, gini=0.3, sugar=40.0, trades=0.0, price=1.0)
    folder = joinpath(dir, name)
    mkpath(folder)
    xxl_line = "xxl vision_shape=\"disc\" speed=(1, 6) free_step=1.5" * (isempty(settings) ? "" : " " * settings)
    write(joinpath(folder, "fingerprint.txt"),
          "julia\n$xxl_line\nlook: centred\n" *
          "Config(width=50, spice=True, credit=(10, 10.0), disease_list=25, diseases_per_agent=10, " *
          "disease_length=(1, 10), immune_length=50, seed=0)\nperiods=$periods\n")
    m = match(r"-s(\d+)-", name)
    first_seed = m === nothing ? 1 : parse(Int, m.captures[1])
    each(x, i) = x isa Function ? x(i) : x
    for i in eachindex(pops)
        cols = [
            list_column(pops[i], periods),
            ever === nothing ? 100.0 .+ (0:periods) : list_column(each(ever, i), periods),
            list_column(sick[i], periods),
            list_column(diseases[i], periods),
            list_column(each(gini, i), periods),
            list_column(each(sugar, i), periods),
            list_column(each(trades, i), periods),
            list_column(each(price, i), periods),
        ]
        write(joinpath(folder, "seed$(first_seed + i - 1).csv"),
              LIST_COLUMNS * "\n" * join(("$(t - 1)," * join((c[t] for c in cols), ",") * "\n" for t in 1:(periods + 1))))
    end
    return folder
end

# A population that starts at 10,000, drops to `low` in period 1 and is `rest` from then on.
list_pop(low, rest; periods=500) = vcat(10000.0, Float64(low), fill(Float64(max(rest, low)), periods - 1))

"""
A screening arm's folder of `n` seeds, `band` of them with a share sick of 0.1 (the rest 0.3, over the band) and
`with_disease` with 5 diseases at every period (the rest none); `sick` gives every seed's share sick instead.
Populations are about 6,000 and spread by `spread` (each seed above or below the 6,000 by that share), and the lowest
populations are `lows` (a number or one a seed) where given. `lengths` and `count` go into the fingerprint's `xxl` line.
"""
function list_arm_folder(dir, name; n=20, band=n, with_disease=n, spread=0.0, lows=nothing, lengths=nothing, count=nothing,
                         sick=nothing, periods=500)
    rest = [6000.0 * (1 + (isodd(i) ? spread : -spread)) for i in 1:n]
    low = lows === nothing ? rest : (lows isa Real ? fill(Float64(lows), n) : Float64.(lows))
    settings = join(
        [count === nothing ? "" : "disease_count=$count", lengths === nothing ? "" : "disease_lengths=$lengths"], " ")
    return list_folder(dir, name;
        pops=[list_pop(low[i], rest[i]; periods) for i in 1:n],
        sick=sick === nothing ? [i <= band ? 0.1 : 0.3 for i in 1:n] : sick,
        diseases=[i <= with_disease ? 5.0 : 0.0 for i in 1:n],
        settings=strip(settings), periods)
end

# The baseline: 20 seeds, their lowest populations 3,000, 7,000 and 5,000 for the other 18 (mean 5,000, minimum 3,000).
list_base_lows() = vcat(3000.0, 7000.0, fill(5000.0, 18))

function list_base(dir; periods=500, name="extinction-base-s20-20-p$periods")
    return Sugarscape.read_list_run("base", list_arm_folder(dir, name; lows=list_base_lows(), periods))
end

"""
An arm of 20 seeds read as a run, named `band<band>` or, where `spread` is given, `spread<spread>`: its lowest populations
those of the baseline, so that it passes the trough, and its length range `hi` (the book's 9–10 at 10, else `hi`–`hi`).
"""
function list_arm(dir; band=20, spread=nothing, hi=10, count=4)
    name = spread === nothing ? "band$band" : "spread$spread"
    lengths = hi == 10 ? (9, 10) : (hi, hi)
    folder = list_arm_folder(dir, "extinction-$name-$(hi)-$(count)-s80-20-p500";
        band, spread=spread === nothing ? 0.1 : spread, lows=list_base_lows(), lengths, count)
    return Sugarscape.read_list_run(name, folder)
end

# A screening run of 20 seeds against the baseline: `in_band` seeds inside the share sick's band, `with_disease` seeds with a
# disease at t = 500, the lowest populations `lows` where given (the baseline's otherwise).
function list_screen(dir, base; in_band=20, with_disease=20, lows=list_base_lows(), sick=nothing, name="screen")
    folder = list_arm_folder(dir, "extinction-$name-s80-20-p500"; band=in_band, with_disease, lows, sick)
    return Sugarscape.screen_arm(Sugarscape.read_list_run(name, folder), base)
end
