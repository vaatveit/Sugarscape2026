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


@pytest.mark.parametrize("mode", ["waves"])
def test_newborn_lender_uids(exe, tmp_path, mode):
    # Fertile from age 0, a newborn can lend in its birth period, before it has a uid: every loan must name real uids.
    cfg = {**_registry("IV-A5", fertility_start="0,0"), **({"inheritance": "true"} if mode == "serial" else {})}
    out = tmp_path / "metrics.csv"
    dump = run_gpu(exe, tmp_path, cfg, steps=20, extra_args=("--out", out))
    assert dump.returncode == 0, dump.stderr
    ever = read_rows(out)[-1]["agents_ever"]
    assert dump.loans, "the scenario must have loans"
    assert all(loan["lender"] < ever and loan["borrower"] < ever for loan in dump.loans)
