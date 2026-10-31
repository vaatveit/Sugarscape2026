# xxl: the loan tracer (docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md, "A loan tracer"). It follows
# each chain of a loan and its rollovers from `seek_credit!` to its end, repaid or voided by a death, as X8 counts, and
# tallies what it sees. It draws no random numbers and changes no loan or agent. Rule L calls the `trace_*` hooks from
# `step!` only when `Model.loan_trace` is set; `timed_seed` calls `trace_period!` after each `step!` and `trace_finish!`
# at the end.
#
# The windows are the periods 1-100, 101-500 and 501-end, as the scorecard labels them: inside `step!`, `m.t` is one
# below the label of the period running, so a window there is `window_index(m.t + 1)`; after it, `window_index(m.t)`.
#
# A tally is a count weighted by the chain's share (1, or 1/k for each of the k copies a dead lender's loan passed to
# under inheritance, so the copies add up to one chain). The tables, by `(window, table, key1, key2)`:
#
#   started, started_bands (lender's band, borrower's band), party_kind (lender|borrower, past_fertile|fertile),
#   party_sex (lender|borrower, sex): at the start; rolled: at each rollover;
#   ended (outcome), void_elapsed (outcome, periods since the chain began), doomed (which party, outcome),
#   principal (outcome; the first principal), received (outcome; sugar the lenders got in all payments),
#   child (outcome, yes|no: the borrower had a child during the chain): at the end;
#   void_cause (party that died, cause), void_age (party that died, its band): at a void, one row per dead party;
#   unfinished: the chains still open when the run stops.
#
# An outcome is repaid, voided_lender, voided_borrower or voided_both.

# The columns of a sampled chain's row, `received` and `weight` as the chain stands (per unit of weight, see `Chain`).
const TRACE_SAMPLE_COLUMNS = [
    "chain",
    "t_start",
    "t_end",
    "outcome",
    "rollovers",
    "weight",
    "lender_id",
    "lender_age",
    "lender_max_age",
    "lender_sex",
    "lender_sugar",
    "borrower_id",
    "borrower_age",
    "borrower_max_age",
    "borrower_sex",
    "borrower_sugar",
    "borrower_income",
    "principal",
    "due",
    "received",
    "child",
    "doomed",
]

"""The window a period's label falls in: 1 for periods 1-100, 2 for 101-500, 3 after."""
window_index(t::Int) = t <= 100 ? 1 : t <= 500 ? 2 : 3

"""An age's 5-year band, named by its lower edge; 95 and over share the last."""
age_band(age::Real) = string(min(Int(fld(age, 5)) * 5, 95))

"""The tally of `table` with these keys in `window`; 0 if nothing was counted."""
function tally(tr::LoanTrace, window::Int, table::String, key1="", key2="")
    return get(tr.tallies, (window, table, string(key1), string(key2)), 0.0)
end

function add!(tr::LoanTrace, window::Int, table::String, value::Real, key1="", key2="")
    key = (window, table, string(key1), string(key2))
    tr.tallies[key] = get(tr.tallies, key, 0.0) + value
    return nothing
end

function take_chain!(tr::LoanTrace, loan::Loan)
    chain = get(tr.chains, loan, nothing)
    chain === nothing && error("the loan trace never saw this loan start: $(loan.lender) lends to $(loan.borrower)")
    delete!(tr.chains, loan)
    return chain
end

"""The first five columns of a party in a sampled row: its id, age, max age, sex and sugar as they stand."""
party_row(a::Agent) = Any[a.id, a.age, a.max_age, string(a.sex), a.sugar]

had_child(chain::Chain, loan::Loan) = length(loan.borrower.children) > chain.children

"""
Which party is certain to die before the loan is settled: `step!` ages and kills before `settle_loans!`, and the loan is
settled d steps after it is made, so a party of age a is doomed when a + d + 1 reaches its max age.
"""
function doomed_class(tr::LoanTrace, lender::Agent, borrower::Agent)
    late = tr.term + 1
    l = lender.age + late >= lender.max_age
    b = borrower.age + late >= borrower.max_age
    return l && b ? "both" : l ? "lender" : b ? "borrower" : "neither"
end

"""A loan `seek_credit!` has just made begins a chain. Call it in `step!`, after the sugar has moved."""
function trace_start!(tr::LoanTrace, m::Model, loan::Loan)
    w = window_index(m.t + 1)
    lender, borrower = loan.lender, loan.borrower
    tr.count += 1
    start = if tr.count % tr.sample_every == 0
        Any[party_row(lender)..., party_row(borrower)..., borrower.last_income]
    else
        nothing
    end
    tr.chains[loan] = Chain(
        tr.count,
        m.t + 1,
        1.0,
        loan.principal,
        loan.due,
        0,
        0.0,
        length(borrower.children),
        doomed_class(tr, lender, borrower),
        start,
    )
    add!(tr, w, "started", 1)
    add!(tr, w, "started_bands", 1, age_band(lender.age), age_band(borrower.age))
    for (role, a) in (("lender", lender), ("borrower", borrower))
        add!(tr, w, "party_kind", 1, role, a.age >= a.fertility_end ? "past_fertile" : "fertile")
        add!(tr, w, "party_sex", 1, role, a.sex)
    end
    return nothing
end

"""The chain of a loan that came due and was paid in full ends. Call it in `settle_loans!`."""
function trace_repaid!(tr::LoanTrace, m::Model, loan::Loan)
    chain = take_chain!(tr, loan)
    chain.received += loan.due / chain.weight
    end_chain!(tr, chain, "repaid", m.t + 1, had_child(chain, loan))
    return nothing
end

"""A due loan the borrower paid `paid` of rolls into `new`: the chain goes on. Call it in `settle_loans!`."""
function trace_rolled!(tr::LoanTrace, m::Model, old::Loan, new::Loan, paid::Real)
    chain = take_chain!(tr, old)
    chain.received += paid / chain.weight
    chain.rollovers += 1
    tr.chains[new] = chain
    add!(tr, window_index(m.t + 1), "rolled", chain.weight)
    return nothing
end

"""
A death voids the loan. Which side died is told in `trace_period!`, at the period's end: a borrower can starve in the
sweep and its lender die of old age later in the period. The borrower's children are read now, before `kill!` empties
them.
"""
function trace_void!(tr::LoanTrace, m::Model, loan::Loan)
    chain = take_chain!(tr, loan)
    push!(tr.voids, (chain, loan, had_child(chain, loan)))
    return nothing
end

"""A dead lender's loan passes to its heirs as `copies`: the chain goes on as a chain per copy, of 1/k the weight."""
function trace_inherit!(tr::LoanTrace, m::Model, old::Loan, copies)
    chain = take_chain!(tr, old)
    weight = chain.weight / length(copies)
    for loan in copies
        # A sampled copy's row describes its lender, the heir, as it stands when the loan passes.
        start = chain.start === nothing ? nothing : vcat(party_row(loan.lender), chain.start[6:end])
        tr.chains[loan] = Chain(
            chain.number,
            chain.t_start,
            weight,
            chain.principal,
            chain.due,
            chain.rollovers,
            chain.received,
            chain.children,
            chain.doomed,
            start,
        )
    end
    return nothing
end

"""Tallies a chain that ended as `outcome` at the end of period `t_end` (a label); keeps its row if it is sampled."""
function end_chain!(tr::LoanTrace, chain::Chain, outcome::String, t_end::Int, child::Bool)
    w, weight = window_index(t_end), chain.weight
    add!(tr, w, "ended", weight, outcome)
    add!(tr, w, "void_elapsed", weight, outcome, t_end - chain.t_start)
    add!(tr, w, "doomed", weight, chain.doomed, outcome)
    add!(tr, w, "principal", weight * chain.principal, outcome)
    add!(tr, w, "received", weight * chain.received, outcome)
    add!(tr, w, "child", weight, outcome, child ? "yes" : "no")
    sample_row!(tr, chain, outcome, t_end, child)
    return nothing
end

function sample_row!(tr::LoanTrace, chain::Chain, outcome::String, t_end, child::Bool)
    chain.start === nothing && return nothing
    push!(
        tr.sampled,
        Any[
            chain.number,
            chain.t_start,
            t_end,
            outcome,
            chain.rollovers,
            chain.weight,
            chain.start...,
            chain.principal,
            chain.due,
            chain.received,
            child ? "yes" : "no",
            chain.doomed,
        ],
    )
    return nothing
end

"""
The end of a period, after `step!`: tells the period's voids apart and tallies them. `m.killed` and each agent's age and
sugar are still as they were, so the cause of death holds. The voids are cleared, so no dead agent outlives its period.
"""
function trace_period!(tr::LoanTrace, m::Model)
    w = window_index(m.t)
    for (chain, loan, child) in tr.voids
        lender, borrower = loan.lender, loan.borrower
        outcome = if !lender.alive && !borrower.alive
            "voided_both"
        elseif !borrower.alive
            "voided_borrower"
        else
            "voided_lender"
        end
        for (party, a) in (("lender", lender), ("borrower", borrower))
            a.alive && continue
            add!(tr, w, "void_cause", chain.weight, party, death_cause(m, a))
            add!(tr, w, "void_age", chain.weight, party, age_band(a.age))
        end
        end_chain!(tr, chain, outcome, m.t, child)
    end
    empty!(tr.voids)
    return nothing
end

"""The run is over: the chains still open are unfinished, as X8 counts them, in the last period's window."""
function trace_finish!(tr::LoanTrace, m::Model)
    w = window_index(m.t)
    open = sort!(collect(tr.chains); by=p -> (p.second.number, p.first.lender.id))  # IdDict order isn't stable
    for (loan, chain) in open
        add!(tr, w, "unfinished", chain.weight)
        sample_row!(tr, chain, "unfinished", "", had_child(chain, loan))
    end
    empty!(tr.chains)
    return nothing
end
