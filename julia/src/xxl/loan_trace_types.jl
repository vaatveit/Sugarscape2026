# xxl: the loan tracer's records. `Model` names `LoanTrace`, so these come before it; the tracer's code is in
# loan_trace.jl, after the scorecard metrics it shares the death causes with.

const CENSUS_EVERY = 50  # periods between the censuses of the living
const SAMPLE_EVERY = 100  # every chain with a number divisible by this is also kept as a raw row

"""
    Chain

One loan and its rollovers (and, under inheritance, its copies) as X8 counts it: begun once, ended once. `weight` is its
share of the chain it began as (1, or 1/k after a dead lender's loan passed to k heirs), `principal` and `due` those of
its first loan, `received` the sugar its lenders got in all payments per unit of weight, `children` the length of the
borrower's `children` when it began, `doomed` which party was certain to die before settlement (`"neither"`, `"lender"`,
`"borrower"` or `"both"`). `start` holds the parties' columns of a sampled chain's row, `nothing` for the others.
"""
mutable struct Chain
    number::Int
    t_start::Int  # the label of the period it began in
    weight::Float64
    principal::Float64
    due::Float64
    rollovers::Int
    received::Float64
    children::Int
    doomed::String
    start::Union{Nothing,Vector{Any}}
end

"""
    LoanTrace(term; census_every=CENSUS_EVERY, sample_every=SAMPLE_EVERY)

An opt-in record of every loan's life for a run (set it as `Model.loan_trace`): the open chains by their current loan,
the voids of the period not yet told apart, the tallies by `(window, table, key1, key2)` and the sampled rows. `term`
is the loan term d. Read the tallies with `tally`.
"""
mutable struct LoanTrace
    term::Int
    census_every::Int
    sample_every::Int
    count::Int  # chains begun so far: the last chain's number
    chains::IdDict{Loan,Chain}
    voids::Vector{Tuple{Chain,Loan,Bool}}  # this period's voided chains, their loan, whether the borrower had a child
    tallies::Dict{Tuple{Int,String,String,String},Float64}
    sampled::Vector{Vector{Any}}
end

function LoanTrace(term::Int; census_every::Int=CENSUS_EVERY, sample_every::Int=SAMPLE_EVERY)
    return LoanTrace(
        term,
        census_every,
        sample_every,
        0,
        IdDict{Loan,Chain}(),
        Tuple{Chain,Loan,Bool}[],
        Dict{Tuple{Int,String,String,String},Float64}(),
        Vector{Any}[],
    )
end
