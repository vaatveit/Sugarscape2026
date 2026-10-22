"""Agent credit rule L_dr (pp.131-133, App. B p.184-185; Intro p.12).

Loans are in sugar on either landscape. Fertility tests sugar only (p.55), so on the
sugar-and-spice landscape (Animation VI-1) nobody ever falls short of spice to have a child,
and a separate spice loan book (Kehoe) would stay empty.
"""

from collections.abc import Collection
from dataclasses import dataclass


@dataclass
class Loan:
    lender: object
    borrower: object
    principal: float
    due: float  # amount owed at due_t
    due_t: int


def _terms(model) -> tuple[int, float]:
    return model.config.credit


def _amount_due(model, principal: float) -> float:
    """Simple interest: principal * (1 + r/100 * d) (Kehoe's reading of "r percent")."""
    d, r = _terms(model)
    return principal * (1 + r / 100 * d)


def available_to_lend(model, agent) -> float:
    """Too old to have children: half its current wealth; of childbearing age: wealth beyond what
    having children needs (its own initial endowment, p.55); otherwise nothing (p.132)."""
    if agent.sex is None or agent.sugar <= 0:
        return 0.0
    if agent.age >= agent.fertility_end:
        return agent.sugar / 2
    if agent.fertility_start <= agent.age and agent.sugar > agent.initial_sugar:
        return agent.sugar - agent.initial_sugar
    return 0.0


def shortfall(model, agent) -> float:
    """Of childbearing age without the wealth to have a child: how much it lacks (p.132)."""
    if agent.sex is None or not (agent.fertility_start <= agent.age < agent.fertility_end):
        return 0.0
    return max(agent.initial_sugar - agent.sugar, 0.0)


def creditworthy(model, borrower, amount_due: float) -> bool:
    """Present income (harvest - metabolism) over the loan's duration covers this loan plus the
    borrower's other obligations (our reading of p.132; the book doesn't define it)."""
    d, _ = _terms(model)
    owed = sum(loan.due for loan in model.loans if loan.borrower is borrower)
    return borrower.last_income * d - owed >= amount_due


def seek_credit(model, agent) -> list[Loan]:
    """A potential borrower asks each neighbor in turn for the sugar it needs (Intro p.12)."""
    need = shortfall(model, agent)
    if need <= 0:
        return []
    d, _ = _terms(model)
    made = []
    neighbors = model.neighbors_of(agent)
    for i in model.rng.permutation(len(neighbors)):
        lender = neighbors[int(i)]
        amount = min(available_to_lend(model, lender), need)
        if amount <= 0 or not creditworthy(model, agent, _amount_due(model, amount)):
            continue
        lender.sugar -= amount
        agent.sugar += amount
        loan = Loan(lender, agent, amount, _amount_due(model, amount), model.t + d)
        model.loans.append(loan)
        made.append(loan)
        need -= amount
        if need <= 0:
            break
    return made


def settle_loans(model) -> None:
    """Loans due now are repaid in full if the borrower can; otherwise it pays half its wealth and
    a new loan with the same terms is originated for the remainder (p.133)."""
    d, _ = _terms(model)
    for loan in [loan for loan in model.loans if loan.due_t == model.t]:
        model.loans.remove(loan)
        borrower, lender = loan.borrower, loan.lender
        if borrower.sugar >= loan.due:
            borrower.sugar -= loan.due
            lender.sugar += loan.due
            continue
        paid = max(borrower.sugar, 0.0) / 2
        borrower.sugar -= paid
        lender.sugar += paid
        rest = loan.due - paid
        model.loans.append(Loan(lender, borrower, rest, _amount_due(model, rest), model.t + d))


def on_death(model, agent, excluded_heirs: Collection = ()) -> None:
    """A dead borrower's loans are the lender's loss; a dead lender's loans are void unless
    inheritance I is on, when its living children become the creditors (p.133)."""
    keep = []
    for loan in model.loans:
        if loan.borrower is agent:
            continue
        if loan.lender is agent:
            # An heir who is the borrower would owe itself: that debt is simply extinguished.
            heirs = [c for c in agent.children if c.alive and c not in excluded_heirs and c is not loan.borrower]
            if model.config.inheritance and heirs:
                k = len(heirs)
                keep.extend(Loan(h, loan.borrower, loan.principal / k, loan.due / k, loan.due_t) for h in heirs)
            continue
        keep.append(loan)
    model.loans[:] = keep
