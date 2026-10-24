"""The agreement rule (design, "Statistical agreement"): Julia's seeds against Python's, metric by metric.

The periods 0..steps are cut into four windows; each seed's value is its mean over a window. Each (metric, window) is
a Welch t-test, extinction is Fisher's exact test, and every p-value in one report is corrected together with
Benjamini-Hochberg. Standard library only: the Student-t tail comes from the regularized incomplete beta function.
"""

import math
from dataclasses import dataclass

from experiments.registry import EXPERIMENTS

Series = list[dict[str, float]]
Q = 0.01


def _betacf(a: float, b: float, x: float) -> float:
    """Continued fraction for the incomplete beta function (modified Lentz)."""
    tiny, eps = 1e-300, 1e-15
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 1000):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            break
    return h


def betainc(a: float, b: float, x: float) -> float:
    """The regularized incomplete beta function I_x(a, b)."""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    front = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x))
    if x < (a + 1.0) / (a + b + 2.0):
        return front * _betacf(a, b, x) / a
    return 1.0 - front * _betacf(b, a, 1.0 - x) / b


def t_sf(t: float, df: float) -> float:
    """P(T > t) for Student's t with df degrees of freedom."""
    tail = 0.5 * betainc(df / 2.0, 0.5, df / (df + t * t))
    return tail if t >= 0 else 1.0 - tail


def _mean(v: list[float]) -> float:
    return sum(v) / len(v)


def _var(v: list[float]) -> float:
    """Sample variance (n - 1)."""
    mu = _mean(v)
    return sum((x - mu) ** 2 for x in v) / (len(v) - 1)


def welch(a: list[float], b: list[float]) -> tuple[float, float, float]:
    """Welch's t-test: (t, degrees of freedom, two-sided p)."""
    va, vb = _var(a) / len(a), _var(b) / len(b)
    se2 = va + vb
    t = (_mean(a) - _mean(b)) / math.sqrt(se2)
    df = se2 * se2 / (va * va / (len(a) - 1) + vb * vb / (len(b) - 1))
    return t, df, min(1.0, 2.0 * t_sf(abs(t), df))


def benjamini_hochberg(p: list[float], q: float) -> list[bool]:
    """Which p-values survive the Benjamini-Hochberg false-discovery-rate correction at level q."""
    m = len(p)
    order = sorted(range(m), key=lambda i: p[i])
    passed = 0
    for rank, i in enumerate(order, start=1):
        if p[i] <= rank * q / m:
            passed = rank
    keep = set(order[:passed])
    return [i in keep for i in range(m)]


def fisher_exact(a: int, b: int, c: int, d: int) -> float:
    """Two-sided Fisher's exact test on [[a, b], [c, d]]: the tables no more likely than this one (scipy's rule)."""
    row1, col1, n = a + b, a + c, a + b + c + d

    def pmf(x: int) -> float:
        return math.comb(row1, x) * math.comb(n - row1, col1 - x) / math.comb(n, col1)

    observed = pmf(a)
    lo, hi = max(0, col1 - (n - row1)), min(row1, col1)
    return min(1.0, sum(pmf(x) for x in range(lo, hi + 1) if pmf(x) <= observed * (1 + 1e-7)))


def windows(steps: int) -> list[tuple[int, int]]:
    """Four equal windows of the periods 0..steps, as inclusive (first, last) t."""
    n = steps + 1
    return [(k * n // 4, (k + 1) * n // 4 - 1) for k in range(4)]


@dataclass
class Check:
    experiment: str
    metric: str | None
    window: int | None  # None for extinction
    kind: str  # tested | identical | constant-differs | untestable | extinction
    p: float
    n_py: int
    n_jl: int
    mean_py: float
    mean_jl: float
    sd_py: float
    flagged: bool = False

    @property
    def diff(self) -> float:
        return self.mean_jl - self.mean_py

    @property
    def diff_sd(self) -> float:
        return self.diff / self.sd_py if self.sd_py and not math.isnan(self.sd_py) else math.nan


def _numbers(runs: list[Series], metric: str) -> list[float]:
    return [v for run in runs for row in run if not math.isnan(v := float(row[metric]))]


def eligible(metric: str, py_runs: list[Series], jl_runs: list[Series]) -> bool:
    """False when the metric is NaN throughout, or one constant throughout, on both sides."""
    values = _numbers(py_runs, metric) + _numbers(jl_runs, metric)
    return bool(values) and min(values) != max(values)


def seed_means(runs: list[Series], metric: str, window: tuple[int, int]) -> list[float]:
    """Each seed's mean of the metric over the window, ignoring NaN; seeds with no number are left out."""
    out = []
    for run in runs:
        values = [float(r[metric]) for r in run if window[0] <= r["t"] <= window[1] and not math.isnan(float(r[metric]))]
        if values:
            out.append(_mean(values))
    return out


def _window_check(exp_id: str, metric: str, w: int, py: list[float], jl: list[float]) -> Check:
    if len(py) < 2 or len(jl) < 2:
        return Check(exp_id, metric, w, "untestable", math.nan, len(py), len(jl),
                     _mean(py) if py else math.nan, _mean(jl) if jl else math.nan, math.nan)
    mean_py, mean_jl, sd_py = _mean(py), _mean(jl), math.sqrt(_var(py))
    args = (len(py), len(jl), mean_py, mean_jl, sd_py)
    if min(py + jl) == max(py + jl):
        return Check(exp_id, metric, w, "identical", 1.0, *args)
    if _var(py) == 0 and _var(jl) == 0:
        return Check(exp_id, metric, w, "constant-differs", math.nan, *args)
    return Check(exp_id, metric, w, "tested", welch(jl, py)[2], *args)


def compare_experiment(exp_id: str, py_runs: list[Series], jl_runs: list[Series]) -> list[Check]:
    """Every check for one experiment: each eligible metric in each window, and extinction."""
    checks = []
    metrics = [k for k in py_runs[0][0] if k != "t"]
    for metric in metrics:
        if not eligible(metric, py_runs, jl_runs):
            continue
        for w, window in enumerate(windows(EXPERIMENTS[exp_id].steps)):
            checks.append(_window_check(exp_id, metric, w, seed_means(py_runs, metric, window),
                                        seed_means(jl_runs, metric, window)))
    py_dead = sum(run[-1]["population"] == 0 for run in py_runs)
    jl_dead = sum(run[-1]["population"] == 0 for run in jl_runs)
    p = fisher_exact(jl_dead, len(jl_runs) - jl_dead, py_dead, len(py_runs) - py_dead)
    checks.append(Check(exp_id, None, None, "extinction", p, len(py_runs), len(jl_runs),
                        py_dead / len(py_runs), jl_dead / len(jl_runs), math.nan))
    return checks


def flag(checks: list[Check], q: float = Q) -> None:
    """Marks the Benjamini-Hochberg survivors among tested windows and extinctions, and every constant-differs."""
    pool = [c for c in checks if c.kind in ("tested", "extinction")]
    for c, keep in zip(pool, benjamini_hochberg([c.p for c in pool], q)):
        c.flagged = keep
    for c in checks:
        if c.kind == "constant-differs":
            c.flagged = True
