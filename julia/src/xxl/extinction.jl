# xxl: the extinction test (stage-2 spec, "The test"). Whether VI-1 under the defaults has under a 5% chance of going
# extinct in 2,000 periods: the upper limit on that chance from the seeds run, one seed's outcome, the verdict and the
# markdown report. The runner that makes the seeds and resumes them is separate.

const EXTINCTION_BAR = 0.05  # the claim: the chance of extinction is below this
const DECLINE_LINE = 0.9  # a seed is falling when its last quarter's mean is below this share of the one before
const EXTINCTION_LAST = 200  # births and deaths are counted over the last this many periods

"""
    extinction_limit(extinct, seeds) -> Float64

The one-sided 95% upper confidence limit on the chance of extinction (exact binomial, Clopper–Pearson): the p at which
`extinct` or fewer of `seeds` going extinct has probability 0.05, by bisection. 1 when `seeds` is 0 or all went extinct.
With no extinctions it is 1 - 0.05^(1 / seeds).
"""
function extinction_limit(extinct::Int, seeds::Int)
    (seeds == 0 || extinct >= seeds) && return 1.0
    # P(X <= extinct) for X ~ Binomial(seeds, p), by the ratio of successive terms.
    function cdf(p)
        term = (1 - p)^seeds
        total = term
        for i in 0:(extinct - 1)
            term *= (seeds - i) / (i + 1) * p / (1 - p)
            total += term
        end
        return total
    end
    lo, hi = 0.0, 1.0  # the cdf falls from 1 at p = 0 to 0 at p = 1
    for _ in 1:100
        mid = (lo + hi) / 2
        cdf(mid) > EXTINCTION_BAR ? (lo = mid) : (hi = mid)
    end
    return (lo + hi) / 2
end

"""
    SeedOutcome

What one seed's run shows, for periods t = 1 to `p` (`p` the last period): the `lowest` population and the first period
`lowest_t` it came at, the population `at_quarters` (t = p÷4, p÷2, 3p÷4, p), `extinct_t` (the first period at 0, else
`nothing`), `births_last` and `deaths_last` over the last `min(EXTINCTION_LAST, p)` periods, the mean population over
the third quarter (p÷2 < t ≤ 3p÷4) and the fourth (3p÷4 < t ≤ p), and the `seconds` the run took (NaN if unknown).
"""
struct SeedOutcome
    seed::Int
    lowest::Float64
    lowest_t::Int
    at_quarters::NTuple{4,Float64}
    extinct_t::Union{Nothing,Int}
    births_last::Int
    deaths_last::Int
    mean_third::Float64
    mean_fourth::Float64
    seconds::Float64
end

"""
    seed_outcome(M, header, seed; seconds=NaN) -> SeedOutcome

One seed's outcome from its run `M` (rows t = 0 to `p`, columns named by `header`; only `t`, `population` and
`agents_ever` are read). Births over the last `w` periods are the change in `agents_ever`; deaths are those births
minus the change in `population`.
"""
function seed_outcome(M::Matrix{Float64}, header::Vector{String}, seed::Int; seconds::Float64=NaN)
    pop, ever = (findfirst(==(name), header) for name in ("population", "agents_ever"))
    p = round(Int, M[end, 1])
    at(t) = M[t + 1, pop]  # row t + 1 is period t
    lowest, lowest_t = findmin(M[2:end, pop])
    dead = findfirst(==(0), M[2:end, pop])
    w = min(EXTINCTION_LAST, p)
    births = round(Int, M[end, ever] - M[end - w, ever])
    return SeedOutcome(
        seed,
        lowest,
        lowest_t,
        (at(p ÷ 4), at(p ÷ 2), at(3p ÷ 4), at(p)),
        dead,
        births,
        births - round(Int, M[end, pop] - M[end - w, pop]),
        mean_of([at(t) for t in (p ÷ 2 + 1):(3p ÷ 4)]),
        mean_of([at(t) for t in (3p ÷ 4 + 1):p]),
        seconds,
    )
end

"""Whether a living seed fell by more than 10% from its third quarter's mean to its fourth's."""
is_falling(o::SeedOutcome) = o.extinct_t === nothing && o.mean_fourth < DECLINE_LINE * o.mean_third

"""
    extinction_verdict(outcomes) -> (; verdict, extinct, limit)

`PASS` when the upper limit on the chance of extinction is below the bar, else `TOO FEW SEEDS` when none went extinct
(more seeds would pass), else `FAIL`.
"""
function extinction_verdict(outcomes::Vector{SeedOutcome})
    extinct = count(o -> o.extinct_t !== nothing, outcomes)
    limit = extinction_limit(extinct, length(outcomes))
    verdict = limit < EXTINCTION_BAR ? "PASS" : extinct == 0 ? "TOO FEW SEEDS" : "FAIL"
    return (; verdict, extinct, limit)
end

"""A share as a percent with two decimals: `4.87`."""
function percent_text(x::Real)
    hundredths = round(Int, 10_000x)
    return "$(hundredths ÷ 100).$(lpad(hundredths % 100, 2, '0'))"
end

seconds_text(s) = isnan(s) ? "—" : string(round(Int, s))

"""
    extinction_report(outcomes; label, rules, first_seed, seeds, periods, jobs, wall) -> String

The markdown report: the verdict and the upper limit, the seeds finished of the `seeds` planned (from `first_seed`) over
`periods`, how many living seeds were falling at the end, the run time (`jobs` and `wall` may be `nothing`), then one
table row per outcome.
"""
function extinction_report(outcomes; label, rules, first_seed, seeds, periods, jobs, wall)
    v = extinction_verdict(collect(SeedOutcome, outcomes))
    finished = length(outcomes)
    living = filter(o -> o.extinct_t === nothing, outcomes)
    falling = count(is_falling, living)
    w = min(EXTINCTION_LAST, periods)
    times = filter(!isnan, [o.seconds for o in outcomes])
    run_time = if isempty(times)
        "—"
    else
        "$(round(Int, sum(times))) s in all, $(round(Int, mean_of(times))) s per seed"
    end
    wall === nothing || (run_time *= "; wall $(round(Int, wall)) s")
    jobs === nothing || (run_time *= " with --jobs $jobs")
    lines = [
        "# Extinction test: $label",
        "",
        "- Verdict: $(v.verdict)",
        "- Bar: below $(fmt(100EXTINCTION_BAR))%, at 95% confidence",
        "- Upper limit on the chance of extinction: $(percent_text(v.limit))%",
        "- Extinct: $(v.extinct) of $finished seeds",
        "- Seeds finished: $finished of $seeds ($(seed_text(first_seed, seeds)))",
        "- Periods: $periods",
        "- Rules: `$(rules_line(rules))`",
        "- Falling at the end: $falling of $(length(living)) living seeds (fell more than 10%, " *
        "t = $(periods ÷ 2 + 1)–$(3periods ÷ 4) against t = $(3periods ÷ 4 + 1)–$periods)",
        "- Run time: $run_time",
    ]
    finished < seeds && push!(
        lines,
        "",
        "**Unfinished: $(seeds - finished) seeds have not run. The verdict covers only those finished.**",
    )
    2falling > length(living) && push!(
        lines,
        "",
        "**Most living seeds were falling at the end: this result says little about longer runs.**",
    )
    push!(
        lines,
        "",
        "| Seed | Lowest | Lowest at t | t = $(periods ÷ 4) | t = $(periods ÷ 2) | t = $(3periods ÷ 4) | " *
        "t = $periods | Extinct at | Births, last $w | Deaths, last $w | Mean, third quarter | " *
        "Mean, fourth quarter | Falling | Seconds |",
        "|" * "---|"^14,
    )
    for o in sort(collect(outcomes); by=o -> o.seed)
        push!(
            lines,
            "| $(o.seed) | $(fmt(o.lowest)) | $(o.lowest_t) | " *
            join((fmt(x) for x in o.at_quarters), " | ") *
            " | $(o.extinct_t === nothing ? "—" : o.extinct_t) | $(o.births_last) | $(o.deaths_last) | " *
            "$(fmt(o.mean_third)) | $(fmt(o.mean_fourth)) | $(is_falling(o) ? "yes" : "no") | " *
            "$(seconds_text(o.seconds)) |",
        )
    end
    return join(lines, "\n") * "\n"
end
