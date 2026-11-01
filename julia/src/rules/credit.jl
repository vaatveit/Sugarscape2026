# Agent credit rule L_dr (pp.131-133, App. B p.184-185; sugarscape/rules/credit.py). Loans are in sugar on either
# landscape: fertility tests sugar only (p.55), so a spice loan book would stay empty.

"""Simple interest: principal * (1 + r/100 * d) (Kehoe's reading of "r percent")."""
function amount_due(m::Model, principal::Float64)
    d, r = m.config.credit
    return principal * (1 + r / 100 * d)
end

"""The sugar having a child requires: the birth endowment (p.55), scaled by Config.fertility_threshold."""
requirement(m::Model, a::Agent) = m.config.fertility_threshold * a.initial_sugar

"""
Too old to have children: half its current wealth; of childbearing age: wealth beyond what having children needs;
otherwise nothing (p.132).
"""
function available_to_lend(m::Model, a::Agent)
    (a.sex === :none || a.sugar <= 0) && return 0.0
    a.age >= a.fertility_end && return a.sugar / 2
    need = requirement(m, a)
    a.fertility_start <= a.age && a.sugar > need && return a.sugar - need
    return 0.0
end

"""
How much more this lender may lend this period: unlimited unless `lender_limit` is on, when it is half the lender's
wealth at its first loan of the period, less what it has lent since (`m.lend_left`; `step!` clears it). Nothing is
stored here, so a refused request doesn't fix the budget. A study option from the credit study's design, not the book.
"""
function lending_left(m::Model, a::Agent)
    m.config.lender_limit || return Inf
    return get(m.lend_left, a.id, a.sugar / 2)
end

"""Of childbearing age without the wealth to have a child: how much it lacks (p.132)."""
function shortfall(m::Model, a::Agent)
    (a.sex === :none || !(a.fertility_start <= a.age < a.fertility_end)) && return 0.0
    return max(requirement(m, a) - a.sugar, 0.0)
end

"""
Present income (harvest - metabolism) over the loan's duration covers this loan plus the borrower's other
obligations (our reading of p.132). `credit_reach` scales the income counted (1 is the reading above).
"""
function creditworthy(m::Model, borrower::Agent, due::Float64)
    d, _ = m.config.credit
    loans = get(m.debts, borrower.id, nothing)
    owed = loans === nothing ? 0.0 : sum((loan.due for loan in loans); init=0.0)
    return borrower.last_income * d * m.config.credit_reach - owed >= due
end

"""Adds a loan to the book, to its borrower's entry in `m.debts` (both keep creation order) and to `m.lent`."""
function add_loan!(m::Model, loan::Loan)
    push!(m.loans, loan)
    push!(get!(Vector{Loan}, m.debts, loan.borrower.id), loan)
    count_lender!(m, loan.lender.id, 1)
    return loan
end

function count_lender!(m::Model, id::Int, change::Int)
    n = get(m.lent, id, 0) + change
    n == 0 ? delete!(m.lent, id) : (m.lent[id] = n)
    return nothing
end

"""Whether the agent is a borrower or a lender in any loan."""
holds_loans(m::Model, a::Agent) = haskey(m.debts, a.id) || haskey(m.lent, a.id)

"""Rebuilds the `m.debts` entries of these borrowers from the loan book, in its order."""
function reindex_debts!(m::Model, ids)
    isempty(ids) && return nothing
    for id in ids
        delete!(m.debts, id)
    end
    for loan in m.loans
        id = loan.borrower.id
        id in ids && push!(get!(Vector{Loan}, m.debts, id), loan)
    end
    return nothing
end

"""
    seek_credit!(m, a) -> loans made

A potential borrower asks each neighbour in turn, in random order, for the sugar it needs (Intro p.12).
"""
function seek_credit!(m::Model, a::Agent)
    made = Loan[]
    need = shortfall(m, a)
    need <= 0 && return made
    d, _ = m.config.credit
    for lender in shuffle!(m.rng, neighbors_of(m, a))
        left = lending_left(m, lender)
        amount = min(available_to_lend(m, lender), left, need)
        (amount <= 0 || !creditworthy(m, a, amount_due(m, amount))) && continue
        lender.sugar -= amount
        m.config.lender_limit && (m.lend_left[lender.id] = left - amount)
        a.sugar += amount
        loan = add_loan!(m, Loan(lender, a, amount, amount_due(m, amount), m.t + d))
        m.loan_trace === nothing || trace_start!(m.loan_trace, m, loan)
        push!(made, loan)
        need -= amount
        need <= 0 && break
    end
    return made
end

"""
Loans due now are repaid in full if the borrower can; otherwise it pays half its wealth and a new loan with the
same terms is originated for the remainder (p.133).
"""
function settle_loans!(m::Model)
    d, _ = m.config.credit
    due = [loan for loan in m.loans if loan.due_t == m.t]
    isempty(due) && return nothing
    filter!(loan -> loan.due_t != m.t, m.loans)
    reindex_debts!(m, Set(loan.borrower.id for loan in due))
    for loan in due
        count_lender!(m, loan.lender.id, -1)
    end
    for loan in due
        borrower, lender = loan.borrower, loan.lender
        if borrower.sugar >= loan.due
            borrower.sugar -= loan.due
            lender.alive && (lender.sugar += loan.due)
            m.loan_trace === nothing || trace_repaid!(m.loan_trace, m, loan)
            continue
        end
        paid = max(borrower.sugar, 0.0) / 2
        borrower.sugar -= paid
        lender.alive && (lender.sugar += paid)
        rest = loan.due - paid
        rolled = add_loan!(m, Loan(lender, borrower, rest, amount_due(m, rest), m.t + d))
        m.loan_trace === nothing || trace_rolled!(m.loan_trace, m, loan, rolled, paid)
    end
    return nothing
end

"""
A dead borrower's loans are the lender's loss; a dead lender's loans are void unless inheritance I is on, when its
living children become the creditors (p.133). An heir who is the borrower would owe itself: that debt is
extinguished. With `claims_outlive_lender` (the credit study's design) a dead lender's loans stand instead, with the
lender as creditor: settling takes the repayment, and `settle_loans!` pays it to no one.
"""
function credit_on_death!(m::Model, a::Agent, excluded_heirs)
    return credit_on_deaths!(m, (a,), excluded_heirs)
end

"""
The loans of every agent in `dying` at once, in one pass over the book: the same book as `credit_on_death!` one
agent at a time when no heir is dying (each is in `excluded_heirs`). Agents without loans cost nothing. A loan whose
borrower and lender both die is void even with `claims_outlive_lender`: no one is left to owe or to be owed.
"""
function credit_on_deaths!(m::Model, dying, excluded_heirs)
    any(a -> holds_loans(m, a), dying) || return nothing
    keep = Loan[]
    lent_to = Set{Int}()  # borrowers whose entries change: the dead's loans to them go to heirs or are void
    for loan in m.loans
        if loan.borrower in dying
            count_lender!(m, loan.lender.id, -1)
            m.loan_trace === nothing || trace_void!(m.loan_trace, m, loan)
            continue
        end
        if loan.lender in dying
            if m.config.claims_outlive_lender
                push!(keep, loan)  # stands, and its `m.lent` count with it
                continue
            end
            push!(lent_to, loan.borrower.id)
            count_lender!(m, loan.lender.id, -1)
            heirs = [
                c for c in loan.lender.children if
                c.alive && !(c in excluded_heirs) && c !== loan.borrower
            ]
            if m.config.inheritance && !isempty(heirs)
                k = length(heirs)
                first_copy = length(keep) + 1
                for h in heirs
                    push!(
                        keep,
                        Loan(
                            h, loan.borrower, loan.principal / k, loan.due / k, loan.due_t
                        ),
                    )
                    count_lender!(m, h.id, 1)
                end
                m.loan_trace === nothing ||
                    trace_inherit!(m.loan_trace, m, loan, view(keep, first_copy:length(keep)))
            else
                m.loan_trace === nothing || trace_void!(m.loan_trace, m, loan)
            end
            continue
        end
        push!(keep, loan)
    end
    empty!(m.loans)
    append!(m.loans, keep)
    for a in dying
        delete!(m.debts, a.id)
    end
    reindex_debts!(m, lent_to)
    return nothing
end
