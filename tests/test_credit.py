import numpy as np
import pytest

from conftest import put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.credit import available_to_lend, seek_credit, settle_loans, shortfall


def credit_model(**kw):  # p.55's threshold (the whole birth endowment) unless a test sets another
    return tiny_model(np.ones((7, 7), dtype=int), sex=True, credit=(10, 10.0), **{"fertility_threshold": 1.0, **kw})


def person(m, x, y, age, sugar, initial=60.0, end=40, income=10.0):
    a = put_agent(m, x, y, sugar=sugar)
    a.sex, a.fertility_start, a.fertility_end = "F", 12, end
    a.age, a.initial_sugar, a.last_income = age, initial, income
    return a


def test_old_agent_lends_half_its_wealth():  # p.132
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    assert available_to_lend(m, old) == 50.0 and shortfall(m, young) == 40.0
    loans = seek_credit(m, young)
    assert len(loans) == 1 and loans[0].principal == 40.0  # shortfall 40 <= 50 available
    assert young.sugar == 60.0 and old.sugar == 60.0 and loans[0].due == pytest.approx(80.0)
    assert loans[0].due_t == m.t + 10 and m.loans == loans


def test_fertile_lender_lends_only_surplus():
    m = credit_model()
    person(m, 3, 3, 20, 70.0)
    poor = person(m, 3, 4, 20, 20.0)
    assert seek_credit(m, poor)[0].principal == 10.0


def test_children_and_the_comfortable_neither_borrow_nor_lend():
    m = credit_model()
    child = person(m, 3, 3, 5, 100.0)
    ok = person(m, 3, 4, 20, 60.0)
    assert available_to_lend(m, child) == 0.0 and shortfall(m, child) == 0.0
    assert available_to_lend(m, ok) == 0.0 and shortfall(m, ok) == 0.0


def test_not_creditworthy_without_income():
    m = credit_model()
    person(m, 3, 3, 50, 100.0)
    poor = person(m, 3, 4, 20, 20.0, income=1.0)
    assert seek_credit(m, poor) == []  # income 1 x d 10 < 80 due


def test_settlement_pays_or_renegotiates():  # p.133
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    loan = seek_credit(m, young)[0]
    m.t = loan.due_t
    young.sugar = 50.0
    settle_loans(m)
    assert young.sugar == 25.0 and old.sugar == 60.0 + 25.0
    (new,) = m.loans
    assert new.principal == pytest.approx(80.0 - 25.0) and new.due_t == m.t + 10 and new.lender is old


def test_settlement_repays_in_full():
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    loan = seek_credit(m, young)[0]
    m.t = loan.due_t
    young.sugar = 100.0
    settle_loans(m)
    assert young.sugar == 20.0 and old.sugar == 140.0 and m.loans == []


def test_deaths_void_or_pass_loans():  # Review Focus 5
    m = credit_model()
    old = person(m, 3, 3, 50, 100.0)
    young = person(m, 3, 4, 20, 20.0)
    seek_credit(m, young)
    m.die(young)
    assert m.loans == [] and old.sugar == 60.0
    m.t = 10
    settle_loans(m)
    assert old.sugar == 60.0
    m2 = credit_model(inheritance=True)
    lender = person(m2, 3, 3, 50, 100.0)
    kid = person(m2, 0, 0, 20, 80.0)
    lender.children = [kid]
    borrower = person(m2, 3, 4, 20, 20.0)
    seek_credit(m2, borrower)
    m2.die(lender)
    assert [l.lender for l in m2.loans] == [kid]
    m3 = credit_model()
    lender3 = person(m3, 3, 3, 50, 100.0)
    seek_credit(m3, person(m3, 3, 4, 20, 20.0))
    m3.die(lender3)
    assert m3.loans == []  # no inheritance: the borrower keeps the loan


def test_credit_runs_in_the_model():
    m = Model(Config(sex=True, credit=(10, 10.0), max_age=(60, 100), endowment=(50, 100), seed=2))
    for _ in range(120):
        m.step()
        assert all(l.lender.alive and l.borrower.alive for l in m.loans)
    assert m.loans


def test_debt_owed_to_a_dead_parent_is_extinguished_not_self_lent():
    m = credit_model(inheritance=True)
    lender = person(m, 3, 3, 50, 100.0)
    kid = person(m, 3, 4, 20, 20.0)
    lender.children = [kid]
    seek_credit(m, kid)
    m.die(lender)
    assert all(loan.lender is not loan.borrower for loan in m.loans) and m.loans == []


def test_spice_landscape_loans_move_sugar_only():  # p.55 sugar-only fertility; Review Focus 5
    m = credit_model(spice=True)
    old, young = person(m, 3, 3, 50, 100.0), person(m, 3, 4, 20, 20.0)
    for a in (old, young):
        a.spice = a.initial_spice = 30.0
    loan = seek_credit(m, young)[0]
    assert loan.principal == 40.0 and young.sugar == 60.0 and old.sugar == 60.0
    assert old.spice == young.spice == 30.0


def test_all_rules_society_runs():  # Animation VI-1 rule set; Review Focus 5
    m = Model(Config(spice=True, trade=True, sex=True, metabolism=(1, 5), spice_metabolism=(1, 5),
                     vision=(1, 5), endowment=(25, 50), initial_population=200, max_age=(60, 100),
                     tag_length=11, culture=True, credit=(10, 10.0), disease_list=25,
                     diseases_per_agent=10, seed=3))
    for _ in range(40):
        m.step()
        assert all(m.agent_at(a.x, a.y) is a for a in m.agents)
        assert all(loan.lender.alive and loan.borrower.alive for loan in m.loans)


def test_credit_follows_the_variant_fertility_threshold():  # needs and surpluses use the same requirement
    m = credit_model(fertility_threshold=0.5)
    rich = person(m, 3, 3, 20, 70.0)
    poor = person(m, 3, 4, 20, 20.0)  # endowed with 60: fertile at 30
    assert shortfall(m, poor) == 10.0 and available_to_lend(m, rich) == 40.0
