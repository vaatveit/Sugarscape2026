"""Credit L (pp.131-133; plan 2026-10-26-gpu-parity-part-c, Tasks 6 and 7).

The scenarios follow Julia's credit_loan_and_repayment (julia/bridge/scenarios.py): a lender past childbearing whose
own turn changes nothing (metabolism 0, nothing to harvest), and a fertile borrower short of its endowment, both female
so nobody mates. Where the order matters, Python is stepped in the GPU's own turn order.
"""

import math

import numpy as np
import pytest

from conftest import run_exe
from gpu import period_orders, read_rows, run_gpu, write_cfg
from reference import python_metric_rows, run_python, run_python_in_order
from test_spice import _registry

CAPACITY = np.zeros((7, 7), dtype=int)
CAPACITY[3, 4] = 10
CREDIT = {"sex": "true", "credit": "10,10.0", "vision": "1,1"}
CREDIT_COLUMNS = ("n_loans", "n_lenders", "n_borrowers", "n_both", "credit_depth")


def _lender(**kw):
    return {"x": 3, "y": 3, "vision": 1, "metabolism": 0, "sugar": 100.0, "age": 50, "max_age": None, "sex": "F",
            "fertility_start": 12, "fertility_end": 40, "initial_sugar": 60.0, **kw}


def _borrower(**kw):
    return {"x": 3, "y": 4, "vision": 1, "metabolism": 0, "sugar": 20.0, "age": 20, "max_age": None, "sex": "F",
            "fertility_start": 12, "fertility_end": 40, "initial_sugar": 60.0, **kw}


def _compare(gpu, py):
    """Sugar to 1e-9, and the books entry by entry."""
    problems = []
    g, p = {a["uid"]: a for a in gpu.agents}, {a["uid"]: a for a in py.agents}
    if set(g) != set(p):
        problems.append(f"agents gpu {sorted(g)} python {sorted(p)}")
    for uid in set(g) & set(p):
        if not math.isclose(g[uid]["sugar"], p[uid]["sugar"], abs_tol=1e-9):
            problems.append(f"agent {uid}: sugar gpu {g[uid]['sugar']} python {p[uid]['sugar']}")
    if len(gpu.loans) != len(py.loans):
        problems.append(f"loans gpu {gpu.loans} python {py.loans}")
    for gl, pl in zip(gpu.loans, py.loans):
        if (gl["lender"], gl["borrower"], gl["due_t"]) != (pl["lender"], pl["borrower"], pl["due_t"]) or not (
                math.isclose(gl["principal"], pl["principal"], abs_tol=1e-9)
                and math.isclose(gl["due"], pl["due"], abs_tol=1e-9)):
            problems.append(f"loan gpu {gl} python {pl}")
    return problems


@pytest.mark.parametrize("t", [1, 10, 12])
def test_loan_and_repayment_matches_python(exe, tmp_path, t):
    agents = [_lender(), _borrower()]
    gpu = run_gpu(exe, tmp_path, CREDIT, CAPACITY, agents, steps=t)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(CREDIT, CAPACITY, agents, t)
    assert _compare(gpu, py) == []
    if t == 1:
        assert len(py.loans) == 1


def test_credit_income_counts_fee(exe, tmp_path):
    # Chapter V (plan 2026-10-27-gpu-parity-part-d, Task 3): the borrower carries "111" with an all-0 immune string,
    # so its income (harvest minus sugar burned) is 1 lower; the lender is immune, so nothing is transmitted.
    cfg = {**CREDIT, "disease_list": "1", "disease_length": "3,3", "immune_length": "10"}
    agents = [_lender(immune="1110000000"), _borrower(immune="0000000000", diseases="0")]
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=1, diseases=["111"])
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, CAPACITY, agents, 1, diseases=["111"])
    assert _compare(gpu, py) == []
    assert len(py.loans) == 1


def test_credit_fee_makes_borrower_unworthy(exe, tmp_path):
    # Final review, Important 1: here creditworthiness binds. Initial sugar 76 makes the borrower need 47, due 94; its
    # income with the fee is 9, and 9 x 10 < 94, so Python lends nothing (without the fee, 10 x 10 >= 94 would lend).
    cfg = {**CREDIT, "disease_list": "1", "disease_length": "3,3", "immune_length": "10"}
    agents = [_lender(immune="1110000000"), _borrower(immune="0000000000", diseases="0", initial_sugar=76.0)]
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=1, diseases=["111"])
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, CAPACITY, agents, 1, diseases=["111"])
    assert py.loans == []
    assert _compare(gpu, py) == []


def test_partial_repayment_reoriginates(exe, tmp_path):
    # The borrower burns 5 a period and harvests 1 after its first: at t = 10 it can't pay the 30 due (rate 50%), so
    # it pays half its sugar and the rest is originated anew, due at t = 20.
    cfg = {**CREDIT, "credit": "10,50.0"}
    agents = [_lender(), _borrower(sugar=50.0, metabolism=5)]
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=11)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, CAPACITY, agents, 11)
    assert _compare(gpu, py) == []
    assert [loan["due_t"] for loan in py.loans] == [20]


def test_old_lender_dies_before_settling(exe, tmp_path):
    # The period-1 loan falls due at t = 1, the period the lender dies of old age: on_death comes first, so the loan is
    # void and the borrower keeps its sugar.
    cfg = {**CREDIT, "credit": "1,10.0"}
    agents = [_lender(max_age=52), _borrower()]
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=2)
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, CAPACITY, agents, 2)
    assert _compare(gpu, py) == []
    assert py.loans == [] and len(py.agents) == 1


def test_starved_lender_loan_void(exe, tmp_path):
    # First in the order, the lender burns to 1 and lends 0.5, then starves in period 2; second, it lends 3 and starves
    # in the same period, and the loan is void after the turns.
    agents = [_lender(sugar=6.0, metabolism=5), _borrower()]
    firsts = set()
    for seed in range(10):
        cfg = {**CREDIT, "seed": str(seed)}
        orders = period_orders(exe, tmp_path / f"o{seed}", cfg, CAPACITY, agents, 2)
        firsts.add(orders[0][0])
        for t in (1, 2):
            (tmp_path / f"{seed}-{t}").mkdir()
            gpu = run_gpu(exe, tmp_path / f"{seed}-{t}", cfg, CAPACITY, agents, steps=t)
            assert gpu.returncode == 0, gpu.stderr
            assert _compare(gpu, run_python_in_order(cfg, CAPACITY, agents, orders[:t])) == [], (seed, t)
    assert firsts == {0, 1}  # both orders occurred


def test_credit_metrics_match_python(exe, tmp_path):
    out = tmp_path / "metrics.csv"
    agents = [_lender(), _borrower()]
    gpu = run_gpu(exe, tmp_path, CREDIT, CAPACITY, agents, steps=12, extra_args=("--out", out))
    assert gpu.returncode == 0, gpu.stderr
    rows = read_rows(out)
    py = python_metric_rows(CREDIT, CAPACITY, agents, steps=12)
    for g, p in zip(rows, py):
        assert [g[c] for c in CREDIT_COLUMNS] == [p[c] for c in CREDIT_COLUMNS], g["t"]
    assert max(r["n_loans"] for r in rows) == 1


CHECK_CASES = {"IV-A5": {}, "IV-A5-stride2": {"vision": "2,6", "look_stride": "2"}}


@pytest.mark.parametrize("name", CHECK_CASES)
def test_credit_check(exe, tmp_path, name):
    cfg = {**_registry("IV-A5"), **CHECK_CASES[name], "steps": "20"}
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg), "--check")
    assert result.returncode == 0, result.stderr


SERIAL_CASES = {"IV-A5": lambda: _registry("IV-A5"), "VI-3-credit": lambda: _registry("VI-3", credit="10,10.0")}


@pytest.mark.parametrize("name", SERIAL_CASES)
def test_serial_equivalence_credit(exe, tmp_path, name):
    from test_sex import _files

    cfg = SERIAL_CASES[name]()
    waves = _files(exe, tmp_path / "waves", cfg, 20)
    assert waves == _files(exe, tmp_path / "serial", cfg, 20, "--serial-turns")
    assert len(waves["loans.csv"]) > 1, "the scenario must have loans"


@pytest.mark.parametrize("mode", ["waves", "serial"])
def test_newborn_lender_uids(exe, tmp_path, mode):
    # Fertile from age 0, a newborn can lend in its birth period, before it has a uid (with inheritance the book names it
    # by its row until birth_uids, k_fix_loans). VI-3's trade lets a newborn pass its endowment, so newborns do lend
    # (IV-A5's never do). Every loan must name real uids, and some must have been lent by an agent born that period.
    cfg = {**_registry("VI-3", credit="10,10.0", fertility_start="0,0"),
           **({"inheritance": "true"} if mode == "serial" else {})}
    newborn_lent = 0
    for seed in range(3):
        tmp = tmp_path / str(seed)
        tmp.mkdir()
        out = tmp / "metrics.csv"
        dump = run_gpu(exe, tmp, {**cfg, "seed": str(seed)}, steps=20, extra_args=("--out", out))
        assert dump.returncode == 0, dump.stderr
        ever = [row["agents_ever"] for row in read_rows(out)]  # ever[t]: agents created by the end of period t
        assert dump.loans, "the scenario must have loans"
        for loan in dump.loans:
            assert loan["lender"] < ever[-1] and loan["borrower"] < ever[-1], loan
            made = loan["due_t"] - 10  # Model.t of the period it was made in (no settling yet in 20 periods)
            newborn_lent += ever[made] <= loan["lender"] < ever[made + 1]
    assert newborn_lent > 0, "no loan was lent by an agent born in the loan's period"


def test_borrower_repaid_to_zero_under_check(exe, tmp_path):
    # The borrower (39 sugar, metabolism 4, a site of 10) borrows 15 in period 1, due 30 at t = 10, and burns 3 a period
    # after: at t = 10 it holds exactly 30 and repays all of it. Python leaves it alive with 0 sugar until its next turn,
    # so --check must accept that.
    agents = [_lender(), _borrower(sugar=39.0, metabolism=4)]
    py = run_python(CREDIT, CAPACITY, agents, 11)
    gpu = run_gpu(exe, tmp_path, CREDIT, CAPACITY, agents, steps=11, extra_args=("--check",))
    assert gpu.returncode == 0, gpu.stderr
    assert _compare(gpu, py) == []
    assert {a["uid"]: a["sugar"] for a in py.agents}[1] == 0.0  # repaid at Model.t = 10, the 11th step: alive with 0


# --- Credit with inheritance (Task 7): loans pass to the lender's heirs, and the turns run one per wave -----------------

INHERIT = {**CREDIT, "inheritance": "true"}
HEIR_CAPACITY = CAPACITY.copy()
HEIR_CAPACITY[3, 2] = 10  # D's site: both borrowers have an income to borrow against


def test_old_lender_heirs_take_loans(exe, tmp_path):
    # L dies of old age at the end of period 1, after lending 10 to its child B and 10 to D. B's loan passes to C alone
    # (B would owe itself); D's splits between B and C, half the principal and the due each, in its place.
    agents = [_lender(max_age=51),
              _borrower(sugar=40.0, parent_a=0),                 # B, L's child, at (3,4): 50 after its harvest
              _borrower(y=2, sugar=40.0),                         # D at (3,2)
              _borrower(x=0, y=0, sugar=10.0, parent_a=0)]        # C, L's other child, alone
    for seed in range(5):
        cfg = {**INHERIT, "seed": str(seed)}
        orders = period_orders(exe, tmp_path / f"o{seed}", cfg, HEIR_CAPACITY, agents, 1)
        (tmp_path / str(seed)).mkdir()
        gpu = run_gpu(exe, tmp_path / str(seed), cfg, HEIR_CAPACITY, agents, steps=1)
        assert gpu.returncode == 0, gpu.stderr
        py = run_python_in_order(cfg, HEIR_CAPACITY, agents, orders)
        assert _compare(gpu, py) == [], seed
        assert sorted((l["lender"], l["borrower"]) for l in py.loans) == [(1, 2), (3, 1), (3, 2)]


def test_starved_lender_heirs_take_loans(exe, tmp_path):
    # L lends in period 1 and starves in period 2 whichever order the turns take; its two children, far apart, each take
    # half of the loan.
    agents = [_lender(sugar=12.0, metabolism=5), _borrower(),
              _borrower(x=0, y=0, sugar=10.0, parent_a=0), _borrower(x=6, y=6, sugar=10.0, parent_a=0)]
    for seed in range(5):
        cfg = {**INHERIT, "seed": str(seed)}
        orders = period_orders(exe, tmp_path / f"o{seed}", cfg, CAPACITY, agents, 2)
        (tmp_path / str(seed)).mkdir()
        gpu = run_gpu(exe, tmp_path / str(seed), cfg, CAPACITY, agents, steps=2)
        assert gpu.returncode == 0, gpu.stderr
        py = run_python_in_order(cfg, CAPACITY, agents, orders)
        assert _compare(gpu, py) == [], seed
        assert py.loans and {l["lender"] for l in py.loans} == {2, 3}


def test_credit_inheritance_serial(exe, tmp_path):
    import json

    timing = tmp_path / "timing.json"
    cfg = {**_registry("IV-A5", inheritance="true"), "steps": "1"}
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg), "--timing", timing)
    assert result.returncode == 0, result.stderr
    t = json.loads(timing.read_text())
    assert t["waves_mean"] == t["agents_start"]


def test_credit_inheritance_check(exe, tmp_path):
    cfg = {**_registry("IV-A5", inheritance="true"), "steps": "20"}
    result = run_exe(exe, "--config", write_cfg(tmp_path, **cfg), "--check")
    assert result.returncode == 0, result.stderr


# --- Part C's deferred minors (plan 2026-10-27-gpu-parity-part-d, Task 4) ------------------------------------------


def test_full_book_reoriginates(exe, tmp_path):
    # A book of exactly its capacity settles and re-originates: test_partial_repayment_reoriginates with room for one.
    cfg = {**CREDIT, "credit": "10,50.0"}
    agents = [_lender(), _borrower(sugar=50.0, metabolism=5)]
    gpu = run_gpu(exe, tmp_path, cfg, CAPACITY, agents, steps=11, extra_args=("--loan-capacity", "1"))
    assert gpu.returncode == 0, gpu.stderr
    py = run_python(cfg, CAPACITY, agents, 11)
    assert _compare(gpu, py) == []
    assert [loan["due_t"] for loan in py.loans] == [20]


def test_book_over_capacity_exits_5(exe, tmp_path):
    # Two old lenders beside the borrower each lend 15 in period 1: two loans, one more than the book holds.
    agents = [_lender(sugar=30.0), _lender(x=2, y=4, sugar=30.0), _borrower()]
    py = run_python(CREDIT, CAPACITY, agents, 1)
    assert len(py.loans) == 2
    (tmp_path / "small").mkdir()
    small = run_gpu(exe, tmp_path / "small", CREDIT, CAPACITY, agents, steps=1, extra_args=("--loan-capacity", "1"))
    assert small.returncode == 5, small.stderr
    assert "loan book capacity 1 exceeded" in small.stderr
    gpu = run_gpu(exe, tmp_path, CREDIT, CAPACITY, agents, steps=1)
    assert gpu.returncode == 0, gpu.stderr
    by_lender = lambda book: sorted(book, key=lambda loan: loan["lender"])  # noqa: E731  (the borrower asks in random order)
    gpu.loans, py.loans = by_lender(gpu.loans), by_lender(py.loans)
    assert _compare(gpu, py) == []


WIDE = np.zeros((24, 24), dtype=int)
WIDE[3, 4] = 10
HEIRS = {"sex": "true", "inheritance": "true", "credit": "10,10.0", "vision": "1,1"}


def _many_children(parent: dict) -> list[dict]:
    """The parent P first, then 33 of its children: one more than a death in a turn may have (MAX_HEIRS)."""
    children = [{"x": 2 * (i % 11), "y": 12 + 2 * (i // 11), "vision": 1, "metabolism": 0, "sugar": 10.0, "age": 0,
                 "max_age": None, "sex": "F", "fertility_start": 12, "fertility_end": 40, "initial_sugar": 10.0,
                 "parent_a": 0} for i in range(33)]
    return [parent, *children]


def test_many_children_non_lender_starves(exe, tmp_path):
    # P starves in its turn and lends nothing, so its 33 children never need counting as loan heirs.
    parent = {"x": 3, "y": 3, "vision": 1, "metabolism": 2, "sugar": 1.0, "age": 30, "max_age": None, "sex": "M",
              "fertility_start": 12, "fertility_end": 50, "initial_sugar": 1.0}
    gpu = run_gpu(exe, tmp_path, HEIRS, np.zeros((24, 24), dtype=int), _many_children(parent), steps=1)
    assert gpu.returncode == 0, gpu.stderr
    assert len(gpu.agents) == 33


def test_many_children_lender_exits_5(exe, tmp_path):
    # P lends to B in period 1 and starves by period 2 in either order: its loan's heirs are beyond the GPU's limit.
    parent = {"x": 3, "y": 3, "vision": 1, "metabolism": 60, "sugar": 100.0, "age": 70, "max_age": None, "sex": "M",
              "fertility_start": 12, "fertility_end": 50, "initial_sugar": 100.0}
    gpu = run_gpu(exe, tmp_path, HEIRS, WIDE, [*_many_children(parent), _borrower()], steps=2)
    assert gpu.returncode == 5, gpu.stderr
    assert "more than 32 heirs" in gpu.stderr
