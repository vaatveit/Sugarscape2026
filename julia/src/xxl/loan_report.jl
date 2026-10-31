# xxl: the loan trace's files and report (docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md, "A script
# and a report"). A seed's trace goes to three files: `seed<k>.tally.csv` (`window,table,key1,key2,value`),
# `seed<k>.census.csv` (`window,group,band,n,children,old_age,sugar,spice,killed`) and `seed<k>.loans.csv` (the sampled
# chains). A seed counts only with all three and its whole CSV (`trace_seed_done`), so a stop between them reruns it
# from period 0. The report answers the spec's four questions in a table per question, by window.
#
# A tally here is a `Dict` keyed by `(window, table, key1, key2)` as text, the census a vector of `CensusRow`s. Anything
# with nothing to divide by is NaN until it is printed, and prints as `—`.

const TRACE_OUTCOMES = ("repaid", "voided_lender", "voided_borrower", "voided_both")
const TRACE_VOIDED = TRACE_OUTCOMES[2:end]
const CENSUS_CAUSES = ("old_age", "sugar", "spice", "killed")
const CENSUS_COLUMNS = ("n", "children", CENSUS_CAUSES...)
# The causes a matched ratio is given for, with their columns in a census row's `(n, children, causes...)`.
const MATCHED_CAUSES = (("all", 3:6), ("old_age", 3:3), ("sugar", 4:4), ("spice", 5:5), ("killed", 6:6))

# Reading lines, from the spec's table.
const AGE_RATIO_BAND = (0.9, 1.1)
const LENDER_ONLY_LINE = 0.5
const DOOMED_LINE = 0.25
const MATCHED_LINE = 1.1
const CHILD_LINE = 1.1
const CREDIT_OFF_LINE = 0.05

const TOOK_LEANS = "Agents who took a loan had to live long enough to take one, so this comparison leans toward credit."

# The windows the report tables, in column order: the window numbers, and the label.
const REPORT_WINDOWS = ([1] => "1–100", [2] => "101–500", [1, 2] => "1–500", [3] => "501–end")

const TraceTally = Dict{NTuple{4,String},Float64}
const CensusRow = NamedTuple{
    (:window, :group, :band, :n, :children, :old_age, :sugar, :spice, :killed),
    Tuple{String,String,String,Float64,Float64,Float64,Float64,Float64,Float64},
}

trace_file(folder::AbstractString, k::Int, kind::AbstractString) = joinpath(folder, "seed$k.$kind.csv")

cell_text(x::AbstractFloat) = format_value(x)
cell_text(x) = string(x)

"""
    write_trace_files(folder, k, tr)

Writes seed `k`'s trace into `folder`: `seed<k>.loans.csv` (the sampled chains), `seed<k>.census.csv` and
`seed<k>.tally.csv`, each moved into place whole. Values print with `format_value`, so they read back exact. The census
tables of `tr.tallies` go to the census file, one row per (window, group, band), and the rest to the tally file.
"""
function write_trace_files(folder::AbstractString, k::Int, tr::LoanTrace)
    loans = IOBuffer()
    println(loans, join(TRACE_SAMPLE_COLUMNS, ","))
    for row in tr.sampled
        println(loans, join((cell_text(x) for x in row), ","))
    end
    write_atomic(trace_file(folder, k, "loans"), String(take!(loans)))

    cells = sort!(collect(Set((key[1], key[3], key[4]) for key in keys(tr.tallies) if startswith(key[2], "census_"))))
    census = IOBuffer()
    println(census, "window,group,band,", join(CENSUS_COLUMNS, ","))
    for (w, group, band) in cells
        fields = (format_value(tally(tr, w, "census_$c", group, band)) for c in CENSUS_COLUMNS)
        println(census, "$w,$group,$band,", join(fields, ","))
    end
    write_atomic(trace_file(folder, k, "census"), String(take!(census)))

    plain_keys = sort!([key for key in keys(tr.tallies) if !startswith(key[2], "census_")])
    plain = IOBuffer()
    println(plain, "window,table,key1,key2,value")
    for key in plain_keys
        println(plain, join(key, ","), ",", format_value(tr.tallies[key]))
    end
    write_atomic(trace_file(folder, k, "tally"), String(take!(plain)))
    return nothing
end

"""A seed's tally file as a dictionary keyed by `(window, table, key1, key2)`."""
function read_tally(path::AbstractString)
    t = TraceTally()
    for line in Iterators.drop(eachline(path), 1)
        w, table, key1, key2, value = split(line, ",")
        t[(String(w), String(table), String(key1), String(key2))] = parse(Float64, value)
    end
    return t
end

"""A seed's census file as a vector of rows (`window, group, band, n, children, old_age, sugar, spice, killed`)."""
function read_census(path::AbstractString)
    rows = CensusRow[]
    for line in Iterators.drop(eachline(path), 1)
        w, group, band, rest... = split(line, ",")
        push!(rows, CensusRow((String(w), String(group), String(band), (parse(Float64, x) for x in rest)...)))
    end
    return rows
end

"""The sum of tallies, over seeds."""
function merge_tallies(list)
    out = TraceTally()
    for t in list, (key, value) in t
        out[key] = get(out, key, 0.0) + value
    end
    return out
end

"""The sum of censuses, over seeds: one row per (window, group, band), in that order."""
function merge_census(list)
    sums = Dict{NTuple{3,String},Vector{Float64}}()
    for rows in list, r in rows
        acc = get!(() -> zeros(6), sums, (r.window, r.group, r.band))
        acc .+= (r.n, r.children, r.old_age, r.sugar, r.spice, r.killed)
    end
    return [CensusRow((key..., acc...)) for (key, acc) in sort!(collect(sums); by=first)]
end

"""Whether seed `k` is done: its CSV is whole and so are its three trace files."""
function trace_seed_done(folder::AbstractString, k::Int, periods::Int)
    seed_done(joinpath(folder, "seed$k.csv"), periods) || return false
    return all(isfile(trace_file(folder, k, kind)) for kind in ("tally", "census", "loans"))
end

# ---- the arithmetic

tget(t, w, table, key1="", key2="") = get(t, (string(w), table, string(key1), string(key2)), 0.0)
tsum(t, windows, table, key1="", key2="") = sum(tget(t, w, table, key1, key2) for w in windows; init=0.0)
share_of(a, b) = b > 0 ? a / b : NaN

"""The `(key1, key2, value)` rows of `table` in `windows`, sorted."""
function trace_rows(t, windows, table)
    ws = Set(string.(windows))
    return sort!([(key[3], key[4], v) for (key, v) in t if key[2] == table && key[1] in ws])
end

"""
    x8_share(t, windows) -> Float64

Voided chains ÷ (voided + repaid) that ended in `windows`: X8's share. NaN if none ended.
"""
function x8_share(t, windows)
    voids = sum(tsum(t, windows, "ended", o) for o in TRACE_VOIDED)
    return share_of(voids, voids + tsum(t, windows, "ended", "repaid"))
end

function census_rows(census, windows, group)
    ws = Set(string.(windows))
    return (r for r in census if r.window in ws && r.group == group)
end
census_deaths(r) = r.old_age + r.sugar + r.spice + r.killed

"""
    age_ratios(t, census, windows; term) -> (; borrower, lender, by_cause, raw)

Observed voids on each side ÷ the voids that mortality at the parties' ages predicts, `term` being the loan's d. Per
window and band, from the census's `all` group (0 with no census): `q_old` is old-age deaths ÷ `n`, `q_starve[c]` for c
in sugar, spice and killed is deaths ÷ `n` × term / (term + 1), as a party faces d sweeps where a census agent faces
d + 1, and `q` is their sum. A chain of lender band bL and borrower band bB expects its borrower's death at
`q[bB] * (1 - q[bL] / 2)` and its lender's at `q[bL] * (1 - q[bB] / 2)`, as a void is seen only if the other party
hasn't already voided the loan. A side adds these over the started chains, × ended ÷ started, since the chains still
open haven't had their chance to die. Windows add before dividing, and a window with no census at all is left out of
both sides. A borrower's side observes `voided_borrower` + `voided_both`, a lender's `voided_lender` + `voided_both`.
`by_cause` gives the same ratio for each cause of death, the observed deaths from `void_cause` and the first factor that
cause's q. `raw` is the ratio before the adjusting, a band's deaths ÷ `n` alone. NaN with nothing expected.
"""
function age_ratios(t, census, windows; term)
    sides = ("borrower", "lender")
    expected = Dict(s => 0.0 for s in sides)
    raw_expected = Dict(s => 0.0 for s in sides)
    observed = Dict(s => 0.0 for s in sides)
    expected_by = Dict(s => Dict(c => 0.0 for c in CENSUS_CAUSES) for s in sides)
    observed_by = Dict(s => Dict(c => 0.0 for c in CENSUS_CAUSES) for s in sides)
    sweeps(c) = c == "old_age" ? 1.0 : term / (term + 1)
    for w in windows
        started = tget(t, w, "started")
        rows = collect(census_rows(census, [w], "all"))
        started > 0 && !isempty(rows) || continue
        ended = sum(tget(t, w, "ended", o) for o in TRACE_OUTCOMES)
        rate(band_q) = Dict(r.band => band_q(r) / r.n for r in rows if r.n > 0)
        raw_q = rate(census_deaths)
        q_by = Dict(c => rate(r -> getfield(r, Symbol(c)) * sweeps(c)) for c in CENSUS_CAUSES)
        q = Dict(band => sum(q_by[c][band] for c in CENSUS_CAUSES) for band in keys(raw_q))
        for (lender_band, borrower_band, count) in trace_rows(t, [w], "started_bands")
            chains = count * ended / started
            q_lender, q_borrower = get(q, lender_band, 0.0), get(q, borrower_band, 0.0)
            for (side, band, other) in (("lender", lender_band, q_borrower), ("borrower", borrower_band, q_lender))
                seen = chains * (1 - other / 2)
                expected[side] += seen * get(q, band, 0.0)
                raw_expected[side] += chains * get(raw_q, band, 0.0)
                for c in CENSUS_CAUSES
                    expected_by[side][c] += seen * get(q_by[c], band, 0.0)
                end
            end
        end
        both = tget(t, w, "ended", "voided_both")
        observed["borrower"] += tget(t, w, "ended", "voided_borrower") + both
        observed["lender"] += tget(t, w, "ended", "voided_lender") + both
        for side in sides, c in CENSUS_CAUSES
            observed_by[side][c] += tget(t, w, "void_cause", side, c)
        end
    end
    ratio(side) = share_of(observed[side], expected[side])
    raw_ratio(side) = share_of(observed[side], raw_expected[side])
    by_cause(side) = Dict(c => share_of(observed_by[side][c], expected_by[side][c]) for c in CENSUS_CAUSES)
    return (;
        borrower=ratio("borrower"),
        lender=ratio("lender"),
        by_cause=(; borrower=by_cause("borrower"), lender=by_cause("lender")),
        raw=(; borrower=raw_ratio("borrower"), lender=raw_ratio("lender")),
    )
end

"""The census's `group` in `windows`, pooled over windows: band => [n, children, old_age, sugar, spice, killed]."""
function pooled_group(census, windows, group)
    out = Dict{String,Vector{Float64}}()
    for r in census_rows(census, windows, group)
        acc = get!(() -> zeros(6), out, r.band)
        acc .+= (r.n, r.children, r.old_age, r.sugar, r.spice, r.killed)
    end
    return out
end

"""
    matched_ratios(census, windows) -> (; borrower, lender, counts, excluded)

Deaths of `borrowing` agents ÷ the deaths expected if they died at the rate of `could_borrow` agents of the same band
in the same window (direct standardization, window by window, as mortality differs between them), for each cause and for
`all`; likewise `lending` against `could_lend`. A (window, band) with no comparison group is left out of both sides, and
its agents add to `excluded`. NaN where nothing is expected. `counts.borrower` and `counts.lender` give, per cause, what
each ratio rests on: `observed`, `expected` and `rate`, the deaths per agent of the bands compared (NaN with no agents).
"""
function matched_ratios(census, windows)
    excluded = 0.0
    function side(group, reference)
        observed = Dict(name => 0.0 for (name, _) in MATCHED_CAUSES)
        expected = Dict(name => 0.0 for (name, _) in MATCHED_CAUSES)
        agents = 0.0
        for w in windows
            g, ref = pooled_group(census, [w], group), pooled_group(census, [w], reference)
            for (band, v) in g
                if !haskey(ref, band) || ref[band][1] <= 0
                    excluded += v[1]
                    continue
                end
                agents += v[1]
                for (name, columns) in MATCHED_CAUSES
                    observed[name] += sum(v[columns])
                    expected[name] += v[1] * sum(ref[band][columns]) / ref[band][1]
                end
            end
        end
        ratios = Dict(name => share_of(observed[name], expected[name]) for (name, _) in MATCHED_CAUSES)
        counts = Dict(
            name => (; observed=observed[name], expected=expected[name], rate=share_of(observed[name], agents)) for
            (name, _) in MATCHED_CAUSES
        )
        return ratios, counts
    end
    borrower, borrower_counts = side("borrowing", "could_borrow")
    lender, lender_counts = side("lending", "could_lend")
    counts = (; borrower=borrower_counts, lender=lender_counts)
    return (; borrower, lender, counts, excluded=round(Int, excluded))
end

"""The share of `borrowing` and of `could_borrow` agents that had a child in the follow-up, over `windows`."""
function child_shares(census, windows)
    function share(group)
        rows = collect(census_rows(census, windows, group))
        return share_of(sum(r.children for r in rows; init=0.0), sum(r.n for r in rows; init=0.0))
    end
    return (; borrowing=share("borrowing"), could_borrow=share("could_borrow"))
end

"""
    child_ratio(census, windows) -> (; ratio, observed, expected, excluded)

Children among `could_borrow_took` agents ÷ the children expected if they had them at the rate of `could_borrow_none`
agents of the same band in the same window (direct standardization, as in [`matched_ratios`](@ref)). A (window, band)
with no `could_borrow_none` agents is left out of both sides, and its agents add to `excluded`. NaN with nothing
expected.
"""
function child_ratio(census, windows)
    observed, expected, excluded = 0.0, 0.0, 0.0
    for w in windows
        took, none = pooled_group(census, [w], "could_borrow_took"), pooled_group(census, [w], "could_borrow_none")
        for (band, v) in took
            if !haskey(none, band) || none[band][1] <= 0
                excluded += v[1]
                continue
            end
            observed += v[2]
            expected += v[1] * none[band][2] / none[band][1]
        end
    end
    return (; ratio=share_of(observed, expected), observed, expected, excluded=round(Int, excluded))
end

"""The agents of `group` over `windows`: how many, the share that had a child in the follow-up, the deaths per agent."""
function group_rates(census, windows, group)
    rows = collect(census_rows(census, windows, group))
    n = sum(r.n for r in rows; init=0.0)
    children = sum(r.children for r in rows; init=0.0)
    return (; n, child_share=share_of(children, n), deaths=share_of(sum(census_deaths, rows; init=0.0), n))
end

"""The weighted median of `(value, weight)` pairs; NaN with no weight."""
function weighted_median(pairs)
    total = sum(w for (_, w) in pairs; init=0.0)
    total > 0 || return NaN
    seen = 0.0
    for (v, w) in sort(pairs; by=first)
        seen += w
        seen >= total / 2 && return Float64(v)
    end
    return NaN
end

"""
Every figure of the report for the chains that ended in `windows` and the censuses taken in them, from the tally `t` and
the `census`, `term` being the loan's d. `age`, `lender_only`, `doomed`, `matched` and `child_ratio` are what
[`trace_readings`](@ref) reads. X8 is not here: it is the mean over seeds of each seed's share, so `summarize_trace`
adds it.
"""
function window_stats(t, census, windows; term)
    ws = collect(windows)
    n(table, key1="", key2="") = tsum(t, ws, table, key1, key2)
    outcomes = Dict(o => n("ended", o) for o in TRACE_OUTCOMES)
    ended = sum(values(outcomes))
    voids = sum(outcomes[o] for o in TRACE_VOIDED)
    sides = ("lender", "borrower")
    causes = Dict(s => Dict(c => n("void_cause", s, c) for c in CENSUS_CAUSES) for s in sides)
    dead = Dict(s => sum(values(causes[s])) for s in sides)
    aged(s) = [(parse(Int, k2), v) for (k1, k2, v) in trace_rows(t, ws, "void_age") if k1 == s]
    dead_ages = Dict(s => aged(s) for s in sides)
    elapsed = Dict(
        o => weighted_median([(parse(Int, k2), v) for (k1, k2, v) in trace_rows(t, ws, "void_elapsed") if k1 == o])
        for o in TRACE_VOIDED
    )
    doomed = sum(n("doomed", d, o) for d in ("lender", "borrower", "both") for o in TRACE_VOIDED)
    principal = Dict(o => n("principal", o) for o in TRACE_OUTCOMES)
    received = Dict(o => n("received", o) for o in TRACE_OUTCOMES)
    lent = sum(values(principal))
    voided_principal = sum(principal[o] for o in TRACE_VOIDED)
    kept = principal["voided_lender"] - received["voided_lender"]
    function kind(role, which)
        both = n("party_kind", role, "past_fertile") + n("party_kind", role, "fertile")
        return share_of(n("party_kind", role, which), both)
    end
    sex(role) = share_of(n("party_sex", role, "F"), n("party_sex", role, "F") + n("party_sex", role, "M"))
    with_child = n("child", "repaid", "yes") + sum(n("child", o, "yes") for o in TRACE_VOIDED)
    return (;
        windows=ws,
        started=n("started"),
        rolled=n("rolled"),
        unfinished=n("unfinished"),
        ended,
        outcomes,
        voids,
        causes,
        dead,
        median_age=Dict(s => weighted_median(dead_ages[s]) for s in sides),
        old_share=Dict(
            s => share_of(sum(v for (b, v) in dead_ages[s] if b >= 60; init=0.0), sum(last, dead_ages[s]; init=0.0)) for
            s in sides
        ),
        elapsed,
        lender_only=share_of(outcomes["voided_lender"], voids),
        doomed=share_of(doomed, voids),
        principal,
        voided_principal,
        voided_share=share_of(voided_principal, lent),
        received_per_lent=share_of(sum(values(received)), lent),
        kept,
        kept_share=share_of(kept, principal["voided_lender"]),
        lender_past_fertile=kind("lender", "past_fertile"),
        borrower_fertile=kind("borrower", "fertile"),
        lender_female=sex("lender"),
        borrower_female=sex("borrower"),
        child_chains=share_of(with_child, ended),
        child_repaid=share_of(n("child", "repaid", "yes"), outcomes["repaid"]),
        age=age_ratios(t, census, ws; term),
        matched=matched_ratios(census, ws),
        child=child_shares(census, ws),
        child_ratio=child_ratio(census, ws),
        took=group_rates(census, ws, "could_borrow_took"),
        none=group_rates(census, ws, "could_borrow_none"),
        cohorts=n("cohorts"),
        census_n=sum(r.n for r in census_rows(census, ws, "all"); init=0.0),
    )
end

# ---- the readings

num(x) = isnan(x) ? "—" : fmt(x)

"""
The sugar and spice ratios of a side of `matched_ratios` that are over the line, each with what it rests on, so a ratio
from a handful of deaths can be weighed. A ratio that can't be read goes to `unread`, under `whose`.
"""
function starving_causes!(unread, ratios, counts, whose)
    over = String[]
    for cause in ("sugar", "spice")
        x = get(ratios, cause, NaN)
        if isnan(x)
            push!(unread, "$whose matched ratio for $cause")
        elseif x > MATCHED_LINE
            c = counts[cause]
            push!(
                over,
                "$cause $(fmt(x)), $(fmt(c.observed)) deaths against $(fmt(c.expected)) expected, " *
                "$(num(c.rate)) per agent",
            )
        end
    end
    return over
end

"""
    trace_readings(s) -> Vector{String}

One line per row of the spec's table ("How the findings are read") that fires on `s`, with its numbers, a note when the
borrowers' extra deaths come from who borrows, then a line for what could not be read (NaN fires nothing) and always a
last line naming the lines checked. `s` has `age`, `lender_only`, `doomed`, `matched` and `child_ratio`, as
`window_stats` gives.
"""
function trace_readings(s)
    lines, unread = String[], String[]
    lo, hi = AGE_RATIO_BAND
    age = s.age
    if isnan(age.borrower) || isnan(age.lender)
        push!(unread, "the age ratio")
    elseif all(x -> lo <= x <= hi, (age.borrower, age.lender))
        push!(
            lines,
            "Age ratio within $(lo)–$(hi) on both sides (borrowers $(fmt(age.borrower)), " *
            "lenders $(fmt(age.lender))): X8 measures lifespan, and loans carry no extra risk.",
        )
    end

    parts = String[]
    if isnan(s.lender_only)
        push!(unread, "the lender-only share of voids")
    elseif s.lender_only > LENDER_ONLY_LINE
        push!(parts, "lender-only voids are $(fmt(s.lender_only)) of voids (over $LENDER_ONLY_LINE)")
    end
    if isnan(s.doomed)
        push!(unread, "the doomed share of voids")
    elseif s.doomed > DOOMED_LINE
        push!(parts, "doomed loans are $(fmt(s.doomed)) of voids (over $DOOMED_LINE)")
    end
    isempty(parts) || push!(lines, join(parts, "; ") * ": X8 mostly reflects the book's rule that the old lend.")

    borrower = s.matched.borrower
    over = starving_causes!(unread, borrower, s.matched.counts.borrower, "the borrowers'")
    isempty(over) || push!(
        lines,
        "Borrowers' matched ratio is over $MATCHED_LINE ($(join(over, "; "))): agents starve more with a loan than " *
        "similar agents without one, a real credit defect.",
    )
    over = starving_causes!(unread, s.matched.lender, s.matched.counts.lender, "the lenders'")
    isempty(over) || push!(
        lines,
        "Lenders' matched ratio is over $MATCHED_LINE ($(join(over, "; "))). Lending may be starving the lender, and " *
        "those deaths void its loans.",
    )

    child = s.child_ratio
    if isnan(child.ratio)
        push!(unread, "the child ratio")
    elseif child.ratio <= CHILD_LINE
        push!(
            lines,
            "Agents who took a loan have a child at $(fmt(child.ratio))× the rate of those who took none, no more " *
            "than $(CHILD_LINE)× ($(fmt(child.observed)) children against $(fmt(child.expected)) expected): credit " *
            "isn't doing its job, whatever X8 says. $TOOK_LEANS",
        )
    end

    all_matched = get(borrower, "all", NaN)
    if !isnan(age.borrower) && !isnan(all_matched) && age.borrower > AGE_RATIO_BAND[2] &&
       AGE_RATIO_BAND[1] <= all_matched <= AGE_RATIO_BAND[2]
        push!(
            lines,
            "Borrowers' age ratio is $(fmt(age.borrower)) but their matched ratio is $(fmt(all_matched)): " *
            "the extra deaths come from who borrows, not from the loan.",
        )
    end

    isempty(unread) || push!(lines, "Could not be read, with nothing to divide by: $(join(unique(unread), "; ")).")
    push!(
        lines,
        "Lines checked: the age ratio within $(lo)–$(hi) on both sides; lender-only voids over $LENDER_ONLY_LINE " *
        "or doomed loans over $DOOMED_LINE of voids; the borrowers' and the lenders' matched ratios over " *
        "$MATCHED_LINE for sugar or spice; agents who took a loan having a child within $(CHILD_LINE)× those who " *
        "took none; the borrowers' age ratio against their matched ratio.",
    )
    return lines
end

"""
    credit_off_reading(base, off) -> Union{Nothing,String}

The spec's last line: when births and the end population (each with `births` and `population`) with credit off are both
within 5% of the baseline's, credit isn't doing its job. `nothing` otherwise, or when either can't be read.
"""
function credit_off_reading(base, off)
    near(a, b) = !isnan(a) && !isnan(b) && b != 0 && abs(a - b) <= CREDIT_OFF_LINE * abs(b)
    near(off.births, base.births) && near(off.population, base.population) || return nothing
    return "With credit off, births ($(fmt(off.births)) against $(fmt(base.births))) and the end population " *
           "($(fmt(off.population)) against $(fmt(base.population))) stay within $(round(Int, 100CREDIT_OFF_LINE))%: " *
           "credit isn't doing its job, whatever X8 says."
end

# ---- the summary

"""
    summarize_trace(seeds, tallies, censuses, seconds; term) -> NamedTuple

The figures of the seeds `seeds`, given each one's tally, census and run time, and the loan's d, `term`: `seeds`,
`per_seed` (seed, loans started, X8 over t = 1–500, seconds), `started`, `x8` (the mean over seeds of each seed's
`x8_share`, as the scorecard takes it) `check` (the `window_stats` of t = 1–500) and `windows`, one `window_stats` with
a `label` for each column of the report's tables. Each has `x8`, the mean over seeds of each seed's share in those
windows, as the scorecard takes it.
"""
function summarize_trace(seeds, tallies, censuses, seconds; term)
    t, census = merge_tallies(tallies), merge_census(censuses)
    present(ws) = any(
        tsum(t, [w], "started") + tsum(t, [w], "ended", "repaid") > 0 || any(r.window == string(w) for r in census)
        for w in ws
    )
    shown = [p for p in REPORT_WINDOWS if present(p.first) && (p.first != [1, 2] || (present([1]) && present([2])))]
    isempty(shown) && (shown = [REPORT_WINDOWS[3]])
    function seed_mean_x8(ws)
        shares = filter(!isnan, [x8_share(tl, ws) for tl in tallies])
        return isempty(shares) ? NaN : mean_of(shares)
    end
    per_seed = [
        (; seed=k, started=tsum(tl, 1:3, "started"), x8=x8_share(tl, 1:2), seconds=s) for
        (k, tl, s) in zip(seeds, tallies, seconds)
    ]
    x8s = filter(!isnan, [p.x8 for p in per_seed])
    return (;
        seeds=collect(seeds),
        per_seed,
        started=tsum(t, 1:3, "started"),
        x8=isempty(x8s) ? NaN : mean_of(x8s),
        check=merge(window_stats(t, census, 1:2; term), (; x8=seed_mean_x8(1:2))),
        windows=[
            merge((; label=p.second), window_stats(t, census, p.first; term), (; x8=seed_mean_x8(p.first))) for
            p in shown
        ],
    )
end

"""
    loan_summary(folder, indices, periods; term) -> NamedTuple

[`summarize_trace`](@ref) of the seeds of `indices` that are done (see [`trace_seed_done`](@ref)), read from `folder`,
with the seconds of each from its timing file. `term` is the loan's d.
"""
function loan_summary(folder::AbstractString, indices, periods::Int; term::Int)
    done = [k for k in indices if trace_seed_done(folder, k, periods)]
    return summarize_trace(
        done,
        [read_tally(trace_file(folder, k, "tally")) for k in done],
        [read_census(trace_file(folder, k, "census")) for k in done],
        [timing_seconds(joinpath(folder, "seed$k.timing.csv")) for k in done];
        term,
    )
end

"""
    trace_matches_scorecard(tally_path, scorecard_csv) -> Bool

Whether the trace's `started`, `rolled`, repaid and voided chains in windows 1 and 2 are exactly the scorecard CSV's
sums of `loans_started`, `loans_rolled`, `loans_repaid` and `loans_voided` over t = 1–100 and 101–500. Only exact
without inheritance, which the scorecard miscounts.
"""
function trace_matches_scorecard(tally_path::AbstractString, scorecard_csv::AbstractString)
    t = read_tally(tally_path)
    header, M = read_seed_csv(scorecard_csv)
    column(name) = M[:, findfirst(==(name), header)]
    for (w, range) in ((1, 1:100), (2, 101:500))
        rows = [i for i in axes(M, 1) if M[i, 1] in range]
        total(name) = sum(column(name)[rows]; init=0.0)
        total("loans_started") == tsum(t, [w], "started") || return false
        total("loans_rolled") == tsum(t, [w], "rolled") || return false
        total("loans_repaid") == tsum(t, [w], "ended", "repaid") || return false
        total("loans_voided") == sum(tsum(t, [w], "ended", o) for o in TRACE_VOIDED) || return false
    end
    return true
end

# ---- the report

count_text(x) = isnan(x) ? "—" : whole_text(x)
band_text(b) = isnan(b) ? "—" : b >= 95 ? "95+" : "$(Int(b))–$(Int(b) + 4)"

"""A table with a column per window of `cols` and a row per `(label, text of a window)` of `rows`."""
function window_table(cols, rows)
    lines = ["| | " * join((c.label for c in cols), " | ") * " |", "|" * "---|"^(length(cols) + 1)]
    for (label, f) in rows
        push!(lines, "| $label | " * join((f(c) for c in cols), " | ") * " |")
    end
    return lines
end

"""
    loan_report(s; label, world, first_seed, seeds, periods, jobs, wall, term) -> String

The markdown report of a [`loan_summary`](@ref) made with the same `term`: the run, a table by window for each of the
spec's four questions, the readings, and a row per seed. Anything with nothing to divide by prints `—`.
"""
function loan_report(s; label, world, first_seed, seeds, periods, jobs, wall, term)
    finished = length(s.seeds)
    times = filter(!isnan, [p.seconds for p in s.per_seed])
    run_time = if isempty(times)
        "—"
    else
        "$(round(Int, sum(times))) s in all, $(round(Int, mean_of(times))) s per seed"
    end
    wall === nothing || (run_time *= "; wall $(round(Int, wall)) s")
    jobs === nothing || (run_time *= " with --jobs $jobs")
    lines = [
        "# Loan trace: $label",
        "",
        "- World: $world",
        "- Seeds finished: $finished of $seeds ($(seed_text(first_seed, seeds)))",
        "- Periods: $periods",
        "- Loans started: $(whole_text(s.started))",
        "- X8, t = 1–500: $(num(s.x8))",
        "- Run time: $run_time",
    ]
    finished < seeds && push!(
        lines,
        "",
        "**Unfinished: $(seeds - finished) of $seeds seeds have not run. The figures cover only those finished.**",
    )
    cols = s.windows
    outcome_share(o) = c -> num(share_of(c.outcomes[o], c.ended))
    cause_share(side, cause) = c -> num(share_of(c.causes[side][cause], c.dead[side]))
    push!(lines, "", "## 1. Who dies", "")
    append!(
        lines,
        window_table(cols, [
            "Loans started" => c -> count_text(c.started),
            "Loans ended" => c -> count_text(c.ended),
            "Rollovers" => c -> count_text(c.rolled),
            "Still open when the run stopped" => c -> count_text(c.unfinished),
            "Repaid, of ended" => outcome_share("repaid"),
            "Voided by the lender, of ended" => outcome_share("voided_lender"),
            "Voided by the borrower, of ended" => outcome_share("voided_borrower"),
            "Voided by both, of ended" => outcome_share("voided_both"),
            "X8, mean over seeds" => c -> num(c.x8),
            (
                "Dead $side: $cause" => cause_share(side, cause) for side in ("lender", "borrower") for
                cause in CENSUS_CAUSES
            )...,
            ("Dead $side: median age" => c -> band_text(c.median_age[side]) for side in ("lender", "borrower"))...,
            ("Dead $side: aged 60 or more" => c -> num(c.old_share[side]) for side in ("lender", "borrower"))...,
            ("Median periods elapsed at a void, $(replace(o, "voided_" => "by "))" =>
                c -> num(c.elapsed[o]) for o in TRACE_VOIDED)...,
        ]),
    )

    function matched(side, cause)
        return function (c)
            n = getfield(c.matched.counts, side)[cause]
            return "$(num(getfield(c.matched, side)[cause])) ($(num(n.observed)) / $(num(n.expected)); " *
                   "$(num(n.rate)) per agent)"
        end
    end
    age(side, cause) = c -> num(cause == "all" ? getfield(c.age, side) : getfield(c.age.by_cause, side)[cause])
    raw_age = "before adjusting for who dies first and for sweeps"
    cohort_row = "Census cohorts, over all seeds" => c -> count_text(c.cohorts)
    push!(lines, "", "## 2. Is a loan riskier than its parties' ages explain?", "")
    append!(
        lines,
        window_table(cols, [
            cohort_row,
            "Agents followed, counted once per census" => c -> count_text(c.census_n),
            "Doomed loans, of voids" => c -> num(c.doomed),
            (
                "Age ratio, $(side)s: $cause" => age(side, cause) for side in (:borrower, :lender) for
                cause in ("all", CENSUS_CAUSES...)
            )...,
            (
                "Age ratio, $(side)s, $raw_age" => c -> num(getfield(c.age.raw, side)) for
                side in (:borrower, :lender)
            )...,
            (
                "Matched ratio, $(side)s: $cause" => matched(side, cause) for side in (:borrower, :lender) for
                cause in ("all", CENSUS_CAUSES...)
            )...,
            "Agents in bands with no comparison group, left out" => c -> count_text(c.matched.excluded),
        ]),
        # The two cohorts of the 1–100 column are whole only once the one at t = 100 has been followed.
        any(c -> c.label == "1–100", cols) && periods > 100 + term ? [
            "",
            "The 1–100 column rests on two cohorts, at t = 50 and 100, whose mortality is below what loans made " *
            "during the trough faced, so its age ratio runs high.",
        ] : String[],
        [
            "",
            "The age ratio is observed voids over those predicted from the death rates of agents of the same age, " *
            "for all deaths and for each cause. The prediction is adjusted for how a loan ends: a void is seen only " *
            "if the other party hasn't already voided the loan, so each side's rate is multiplied by 1 less half the " *
            "other side's; and a party faces $term sweeps where a census agent faces $(term + 1), so the sugar, " *
            "spice and killed rates are scaled by $term/$(term + 1). " *
            "The matched ratio is the death rate of borrowing (lending) agents over that of could-borrow " *
            "(could-lend) agents of the same age band, shown as ratio (deaths seen / expected; deaths per agent).",
            "",
            "The groups aren't randomized, so the matched figures are evidence, not proof.",
        ],
    )

    push!(lines, "", "## 3. What does it cost, in sugar?", "")
    append!(
        lines,
        window_table(cols, [
            ("Principal voided, $(replace(o, "voided_" => "by "))" => c -> num(c.principal[o]) for
             o in TRACE_VOIDED)...,
            "Share of principal voided" => c -> num(c.voided_share),
            "Received by lenders per unit lent" => c -> num(c.received_per_lent),
            "Kept by borrowers when a lender died (principal less paid)" => c -> num(c.kept),
            "Kept, per unit of those loans' principal" => c -> num(c.kept_share),
        ]),
    )

    push!(lines, "", "## 4. Does credit do its job?", "")
    append!(
        lines,
        window_table(cols, [
            cohort_row,
            "Agents followed, counted once per census" => c -> count_text(c.census_n),
            "Lenders past childbearing age" => c -> num(c.lender_past_fertile),
            "Borrowers of childbearing age" => c -> num(c.borrower_fertile),
            "Lenders who are female" => c -> num(c.lender_female),
            "Borrowers who are female" => c -> num(c.borrower_female),
            "Chains whose borrower had a child" => c -> num(c.child_chains),
            "Repaid chains whose borrower had a child" => c -> num(c.child_repaid),
            "Took a loan against took none, a child, standardized" => c -> num(c.child_ratio.ratio),
            "Children among those who took a loan" => c -> num(c.child_ratio.observed),
            "Children expected at the rate of those who took none" => c -> num(c.child_ratio.expected),
            "Took a loan, in bands with no comparison group, left out" => c -> count_text(c.child_ratio.excluded),
            "Took a loan: with a child" => c -> num(c.took.child_share),
            "Took none: with a child" => c -> num(c.none.child_share),
            "Took a loan: deaths per agent" => c -> num(c.took.deaths),
            "Took none: deaths per agent" => c -> num(c.none.deaths),
        ]),
        [
            "",
            "Could-borrow agents are split by whether they were seen owing a loan during the follow-up. $TOOK_LEANS",
            "",
            "Borrowing against could-borrow: contaminated, as most could-borrow agents take a loan during the " *
            "follow-up.",
            "",
        ],
        window_table(cols, [
            "Borrowing agents with a child (census)" => c -> num(c.child.borrowing),
            "Could-borrow agents with a child (census)" => c -> num(c.child.could_borrow),
        ]),
    )

    push!(lines, "", "## Reading", "", "### t = 1–500, X8's own window", "")
    append!(lines, ("- $l" for l in trace_readings(s.check)))
    late = findfirst(c -> c.label == "501–end", s.windows)
    if late !== nothing
        push!(lines, "", "### t = 501–end", "")
        append!(lines, ("- $l" for l in trace_readings(s.windows[late])))
    end

    push!(lines, "", "## Seeds", "", "| Seed | Loans started | X8, t = 1–500 | Seconds |", "|---|---|---|---|")
    for p in sort(s.per_seed; by=p -> p.seed)
        push!(lines, "| $(p.seed) | $(whole_text(p.started)) | $(num(p.x8)) | $(seconds_text(p.seconds)) |")
    end
    return join(lines, "\n") * "\n"
end
