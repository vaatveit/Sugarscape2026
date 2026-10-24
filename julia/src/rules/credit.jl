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

"""Of childbearing age without the wealth to have a child: how much it lacks (p.132)."""
function shortfall(m::Model, a::Agent)
    (a.sex === :none || !(a.fertility_start <= a.age < a.fertility_end)) && return 0.0
    return max(requirement(m, a) - a.sugar, 0.0)
end

"""
Present income (harvest - metabolism) over the loan's duration covers this loan plus the borrower's other
obligations (our reading of p.132).
"""
function creditworthy(m::Model, borrower::Agent, due::Float64)
    d, _ = m.config.credit
    owed = sum((loan.due for loan in m.loans if loan.borrower === borrower); init=0.0)
    return borrower.last_income * d - owed >= due
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
        amount = min(available_to_lend(m, lender), need)
        (amount <= 0 || !creditworthy(m, a, amount_due(m, amount))) && continue
        lender.sugar -= amount
        a.sugar += amount
        loan = Loan(lender, a, amount, amount_due(m, amount), m.t + d)
        push!(m.loans, loan)
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
    for loan in due
        borrower, lender = loan.borrower, loan.lender
        if borrower.sugar >= loan.due
            borrower.sugar -= loan.due
            lender.sugar += loan.due
            continue
        end
        paid = max(borrower.sugar, 0.0) / 2
        borrower.sugar -= paid
        lender.sugar += paid
        rest = loan.due - paid
        push!(m.loans, Loan(lender, borrower, rest, amount_due(m, rest), m.t + d))
    end
    return nothing
end

"""
A dead borrower's loans are the lender's loss; a dead lender's loans are void unless inheritance I is on, when its
living children become the creditors (p.133). An heir who is the borrower would owe itself: that debt is
extinguished.
"""
function credit_on_death!(m::Model, a::Agent, excluded_heirs)
    keep = Loan[]
    for loan in m.loans
        loan.borrower === a && continue
        if loan.lender === a
            heirs = [
                c for
                c in a.children if c.alive && !(c in excluded_heirs) && c !== loan.borrower
            ]
            if m.config.inheritance && !isempty(heirs)
                k = length(heirs)
                append!(
                    keep,
                    (
                        Loan(
                            h, loan.borrower, loan.principal / k, loan.due / k, loan.due_t
                        ) for h in heirs
                    ),
                )
            end
            continue
        end
        push!(keep, loan)
    end
    empty!(m.loans)
    append!(m.loans, keep)
    return nothing
end
