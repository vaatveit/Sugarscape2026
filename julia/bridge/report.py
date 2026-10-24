"""Compare Julia results with Python's and write <julia dir>/REPORT.md: agreement, book targets, and speed.

Usage (from julia/): python -m bridge.report [--xl] [--only PREFIX] [--julia DIR] [--python DIR]
Nothing is run: the report reads what both sides saved and says what is missing, stale or untimed.
"""

import argparse
import math
import statistics
from dataclasses import dataclass, field
from pathlib import Path

from bridge.agreement import Q, Check, compare_experiment, flag, windows
from bridge.paths import PY_RESULTS, REPO_ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import _read_csv, fingerprint, load_results, result_dir
from replication.report import Result, _fmt, evaluate
from replication.targets import TARGETS, Target
from sugarscape.config import Config


@dataclass
class Speed:
    experiment: str
    python_setup: float | None
    julia_setup: float | None
    python_step: float | None  # seconds per period
    julia_step: float | None
    python_metrics: float | None  # seconds per recorded period
    julia_metrics: float | None
    agents_start: float | None  # Julia's means
    agents_end: float | None
    python_machine: dict[str, str]
    julia_machine: dict[str, str]

    @property
    def speedup(self) -> float | None:
        """Python's stepping time per period over Julia's."""
        if self.python_step is None or not self.julia_step:
            return None
        return self.python_step / self.julia_step


@dataclass
class TargetRow:
    target: Target
    python: Result | None
    julia: Result | None

    @property
    def changed(self) -> bool:
        return self.python is not None and self.julia is not None and self.python.status != self.julia.status


@dataclass
class Report:
    xl: bool
    tests: list[Check] = field(default_factory=list)
    inputs: dict[str, dict[str, list[str]]] = field(default_factory=dict)
    targets: list[TargetRow] = field(default_factory=list)
    speed: list[Speed] = field(default_factory=list)

    @property
    def flags(self) -> list[Check]:
        return [t for t in self.tests if t.flagged]

    @property
    def agrees(self) -> bool:
        return bool(self.tests) and not self.flags and not any(t.changed for t in self.targets)


def _seed_files(folder: Path) -> list[Path]:
    return list(folder.glob("seed*.csv")) if folder.is_dir() else []


def _status(exp_id: str, root: Path, xl: bool, prefix: str) -> list[str]:
    folder = result_dir(exp_id, root)
    if not _seed_files(folder):
        return ["missing"]
    out = []
    fp = folder / "fingerprint.txt"
    if not fp.exists() or fp.read_text(encoding="utf-8") != prefix + fingerprint(exp_id, xl):
        out.append("stale")
    if len(_seed_files(folder)) < EXPERIMENTS[exp_id].seeds:
        out.append("incomplete")
    if not (folder / "timing.csv").exists():
        out.append("untimed")
    return out


def _machine(folder: Path) -> dict[str, str]:
    path = folder / "machine.txt"
    if not path.exists():
        return {}
    pairs = (line.split(" = ", 1) for line in path.read_text(encoding="utf-8").splitlines() if " = " in line)
    return {k: v for k, v in pairs}


def _timing(folder: Path) -> tuple[float, float, float, float, float] | None:
    """Mean setup s, stepping s per period, metrics s per recorded period, agents at start and end."""
    path = folder / "timing.csv"
    if not path.exists():
        return None
    rows = _read_csv(path)
    mean = lambda f: statistics.fmean(f(r) for r in rows)  # noqa: E731
    return (mean(lambda r: r["setup_s"]), mean(lambda r: r["stepping_s"] / max(r["periods"], 1)),
            mean(lambda r: r["metrics_s"] / (r["periods"] + 1)), mean(lambda r: r["agents_start"]),
            mean(lambda r: r["agents_end"]))


def _speed(exp_id: str, py_root: Path, jl_root: Path) -> Speed:
    py_folder, jl_folder = result_dir(exp_id, py_root), result_dir(exp_id, jl_root)
    py, jl = _timing(py_folder), _timing(jl_folder)
    py, jl = py or (None,) * 5, jl or (None,) * 5
    return Speed(exp_id, py[0], jl[0], py[1], jl[1], py[2], jl[2], jl[3], jl[4], _machine(py_folder),
                 _machine(jl_folder))


def _targets(ids: set[str], jl_root: Path, py_root: Path, cache: dict) -> list[TargetRow]:
    def runs(exp_id: str, root: Path):
        key = (exp_id, str(root))
        if key not in cache:
            cache[key] = load_results(exp_id, root) if _seed_files(result_dir(exp_id, root)) else None
        return cache[key]

    rows = []
    for t in TARGETS:
        if t.experiment not in ids:
            continue
        scored = []
        for root in (py_root, jl_root):
            main, base = runs(t.experiment, root), runs(t.baseline, root) if t.baseline else None
            try:
                scored.append(None if main is None or (t.baseline and base is None) else evaluate(t, main, base))
            except KeyError:  # a column this result does not record
                scored.append(None)
        rows.append(TargetRow(t, *scored))
    return rows


def build_report(julia_dir: Path, python_dir: Path, xl: bool = False, only: str | None = None) -> Report:
    report = Report(xl)
    ids = [i for i, e in EXPERIMENTS.items() if isinstance(e.config, Config) and (only is None or i.startswith(only))]
    cache: dict = {}
    compared = set()
    for exp_id in ids:
        py_status = _status(exp_id, Path(python_dir), xl, "")
        jl_status = _status(exp_id, Path(julia_dir), xl, "julia\n")
        if py_status == ["missing"] and jl_status == ["missing"]:
            continue
        report.inputs[exp_id] = {"python": py_status, "julia": jl_status}
        report.speed.append(_speed(exp_id, Path(python_dir), Path(julia_dir)))
        if "missing" in py_status or "missing" in jl_status:
            continue
        py_runs, jl_runs = load_results(exp_id, Path(python_dir)), load_results(exp_id, Path(julia_dir))
        cache[(exp_id, str(python_dir))], cache[(exp_id, str(julia_dir))] = py_runs, jl_runs
        report.tests += compare_experiment(exp_id, py_runs, jl_runs)
        compared.add(exp_id)
    flag(report.tests, Q)
    if not xl:  # the book's targets are absolute numbers for the 50x50 world (xl design, Non-goals)
        report.targets = _targets(compared, Path(julia_dir), Path(python_dir), cache)
    return report


def _window_label(exp_id: str, w: int | None) -> str:
    if w is None:
        return "end"
    a, b = windows(EXPERIMENTS[exp_id].steps)[w]
    return f"{a}–{b}"


def _num(v: float | None, digits: int = 4) -> str:
    return "—" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.{digits}g}"


def _machine_label(m: dict[str, str]) -> str:
    if not m:
        return "—"
    note = m.get("user_note")
    return f"jobs {m.get('jobs', '?')}" + (f", {note}" if note else "")


def write_report(report: Report, path: Path) -> None:
    kind = "xl" if report.xl else "regular"
    tested = sum(t.kind == "tested" for t in report.tests)
    extinctions = sum(t.kind == "extinction" for t in report.tests)
    changes = [t for t in report.targets if t.changed]
    lines = [f"# Julia vs Python comparison ({kind} size)", ""]
    verdict = "agrees with" if report.agrees else "does not agree with"
    lines += [f"**Julia {verdict} Python** on {len({t.experiment for t in report.tests})} experiments: "
              f"{len(report.flags)} flags among {tested} tested windows and {extinctions} extinction tests "
              f"(Benjamini–Hochberg, q = {Q}), and {len(changes)} book-target status changes.", ""]

    issues = {i: s for i, s in report.inputs.items() if s["python"] or s["julia"]}
    lines += ["## Inputs", "",
              f"{len(report.inputs) - len(issues)} experiments have current, complete, timed results on both sides.",
              ""]
    if issues:
        lines += ["| Experiment | Python | Julia |", "|---|---|---|"]
        lines += [f"| {i} | {', '.join(s['python']) or 'ok'} | {', '.join(s['julia']) or 'ok'} |"
                  for i, s in issues.items()]
        lines.append("")

    lines += ["## Flags", ""]
    flags = sorted(report.flags, key=lambda t: (t.kind != "constant-differs", t.p))
    if flags:
        lines += ["| Experiment | Metric | Window (t) | Kind | Python mean | Julia mean | Julia − Python | "
                  "In Python SDs | p |", "|---|---|---|---|---|---|---|---|---|"]
        for t in flags:
            metric = "extinctions (share of seeds)" if t.kind == "extinction" else t.metric
            lines.append(f"| {t.experiment} | {metric} | {_window_label(t.experiment, t.window)} | {t.kind} | "
                         f"{_num(t.mean_py)} | {_num(t.mean_jl)} | {_num(t.diff)} | {_num(t.diff_sd, 3)} | "
                         f"{_num(t.p, 3)} |")
    else:
        lines.append("None.")
    lines.append("")

    untestable: dict[str, int] = {}
    for t in report.tests:
        if t.kind == "untestable":
            untestable[t.experiment] = untestable.get(t.experiment, 0) + 1
    lines += ["## Untestable windows", "",
              "Fewer than two seeds with a value on a side: after an extinction (tested instead as extinction), or "
              "once the measured group is gone, such as agents of vision 2 or less after selection.", ""]
    lines += [f"- {i}: {n}" for i, n in untestable.items()] or ["None."]
    lines.append("")

    if not report.xl:
        lines += ["## Book targets", ""]
        for side in ("python", "julia"):
            results = [getattr(t, side) for t in report.targets]
            counts = ", ".join(f"{sum(r is not None and r.status == s for r in results)} {s}"
                               for s in ("pass", "near", "fail"))
            lines.append(f"- {side.capitalize()}: {counts}, {sum(r is None for r in results)} not scored.")
        lines += ["", "Status changes:", ""]
        lines += [f"- {t.target.experiment} {t.target.name}: Python {t.python.status} → Julia {t.julia.status} "
                  f"(Python {_fmt(t.python.observed_mean)}, Julia {_fmt(t.julia.observed_mean)}, band "
                  f"{_fmt(t.target.low)}–{_fmt(t.target.high)})" for t in changes] or ["None."]
        lines += ["", "| Experiment | Target | Band | Python mean | Python | Julia mean | Julia |",
                  "|---|---|---|---|---|---|---|"]
        for t in report.targets:
            py = "—" if t.python is None else t.python.status
            jl = "—" if t.julia is None else t.julia.status
            lines.append(f"| {t.target.experiment} | {t.target.name} | {_fmt(t.target.low)}–{_fmt(t.target.high)} | "
                         f"{_fmt(t.python.observed_mean) if t.python else '—'} | {py} | "
                         f"{_fmt(t.julia.observed_mean) if t.julia else '—'} | {jl} |")
        lines.append("")

    speedups = [s.speedup for s in report.speed if s.speedup is not None]
    lines += ["## Speed", "",
              "Development timings, uncontrolled: the machine was shared with other work, and an i7-13700K mixes "
              "performance and efficiency cores. Headline numbers come from the quiet-machine runs.", "",
              f"Median speedup (Python ÷ Julia seconds per period): {_num(statistics.median(speedups), 3) if speedups else '—'}"
              f" over {len(speedups)} experiments timed on both sides.", "",
              "| Experiment | Python s/period | Julia s/period | Speedup | Python setup s | Julia setup s | "
              "Python metrics s | Julia metrics s | Julia agents start → end | Python | Julia |",
              "|---|---|---|---|---|---|---|---|---|---|---|"]
    for s in report.speed:
        lines.append(f"| {s.experiment} | {_num(s.python_step)} | {_num(s.julia_step)} | {_num(s.speedup, 3)} | "
                     f"{_num(s.python_setup)} | {_num(s.julia_setup)} | {_num(s.python_metrics)} | "
                     f"{_num(s.julia_metrics)} | {_num(s.agents_start, 6)} → {_num(s.agents_end, 6)} | "
                     f"{_machine_label(s.python_machine)} | {_machine_label(s.julia_machine)} |")
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--xl", action="store_true")
    parser.add_argument("--only", default=None, help="experiment ids starting with this, e.g. II- or VAR-")
    parser.add_argument("--julia", type=Path, default=None)
    parser.add_argument("--python", type=Path, default=None)
    args = parser.parse_args(argv)
    suffix = "-xl" if args.xl else ""
    julia = args.julia or REPO_ROOT / f"results-julia{suffix}"
    python = args.python or PY_RESULTS / f"results{suffix}"
    report = build_report(julia, python, args.xl, args.only)
    write_report(report, julia / "REPORT.md")
    print(f"wrote {julia / 'REPORT.md'}: {'agrees' if report.agrees else 'does not agree'}; "
          f"{len(report.flags)} flags, {sum(t.changed for t in report.targets)} target status changes")


if __name__ == "__main__":
    main()
