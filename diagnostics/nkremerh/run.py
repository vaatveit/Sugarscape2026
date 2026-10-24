"""Run nkremerh/sugarscape (Nathan Kremer-Herman, Python; github.com/nkremerh/sugarscape) headless on Figs III-1, III-3,
III-4 and III-5, on its own generated landscape and on the book's map, and write each run as rows in the MASON
harness's format (RS,t,population,population,mean vision,mean metabolism).

Each run starts from the repository's own Chapter III example (examples/reproduction_basic.json: 400 agents, vision
1-6, metabolism 1-4, ages 60-100, fertility from 12-15, each parent paying half its starting sugar) and sets only the
figure's stated endowment and fertility ends (p.64, p.65), the seed and the length. "preset" figures use the
repository's own III-4/III-5 examples, which set starting sugar 20-80 where p.65 says 10-40. The model runs in its own
process from the clone (with -E -s); nothing from it is imported here.

Usage: run.py <clone of nkremerh/sugarscape> <work folder> [seeds] [jobs]
"""
import csv
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
FIGURES = {  # figure: (starting sugar, female infertility ages, male infertility ages, steps)
    "1": ((50, 100), (40, 50), (50, 60), 2500),
    "3": ((50, 100), (30, 40), (40, 50), 2500),
    "4": ((10, 40), (40, 50), (50, 60), 2500),
    "5": ((10, 40), (30, 40), (40, 50), 1500),
    "4preset": ((20, 80), (40, 50), (50, 60), 2500),
    "5preset": ((20, 80), (30, 40), (40, 50), 1500),
}
MAPS = ("own", "book")


def book_map(path):
    """The book's map in the repository's environmentFile format: [x][y] -> {"sugar", "spice"}. The repository's
    loader (Sugarscape.configureEnvironment) passes a cell's spice where Cell expects its sugar and vice versa, so
    the capacities go in the "spice" field to land on the sugar layer."""
    cap = np.loadtxt(ROOT / "sugarscape" / "maps" / "sugar-map.txt", dtype=int)
    path.write_text(json.dumps([[{"sugar": 0, "spice": int(c)} for c in row] for row in cap]))


def run(clone, work, fig, landscape, seed):
    sugar, female, male, steps = FIGURES[fig]
    conf = json.loads((clone / "examples" / "reproduction_basic.json").read_text())
    conf.update({"agentStartingSugar": list(sugar), "agentFemaleInfertilityAge": list(female),
                 "agentMaleInfertilityAge": list(male), "seed": seed, "timesteps": steps, "headlessMode": True,
                 "logfileFormat": "csv"})
    name = f"fig3-{fig}_{landscape}_seed{seed}"
    log = work / "logs" / f"{name}.csv"
    conf["logfile"] = str(log)
    if landscape == "book":
        conf["environmentFile"] = str(work / "book-map.json")
    conf_path = work / "conf" / f"{name}.json"
    conf_path.write_text(json.dumps(conf))
    log.unlink(missing_ok=True)
    subprocess.run([sys.executable, "-E", "-s", str(clone / "sugarscape.py"), "--conf", str(conf_path)],
                   cwd=work, check=True, stdout=subprocess.DEVNULL)
    with log.open(newline="") as f:
        rows = list(csv.DictReader(f))
    lines = [f"# nkremerh/sugarscape {conf}", f"RS,0,400,400,nan,nan"]
    rows = [r for r in rows if int(r["timestep"]) > 0]  # the log opens with a row of zeros at t=0
    for r in rows:
        n = int(float(r["population"]))
        lines.append(f"RS,{r['timestep']},{n},{n},{r['meanVision']},{r['meanMetabolism']}")
    last = int(rows[-1]["timestep"]) if rows else 0
    if not rows or int(float(rows[-1]["population"])) > 0 and last < steps - 1:
        lines.append(f"RS,{last + 1},0,0,nan,nan")  # the log stops without a row when the society dies out
    (work / "runs" / f"{name}.csv").write_text("\n".join(lines) + "\n")
    return name


if __name__ == "__main__":
    clone, work = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    seeds = int(sys.argv[3]) if len(sys.argv) > 3 else 10
    jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    for sub in ("logs", "conf", "runs"):
        (work / sub).mkdir(parents=True, exist_ok=True)
    book_map(work / "book-map.json")
    tasks = [(f, m, s) for m in MAPS for f in FIGURES for s in range(1, seeds + 1)]
    with ThreadPoolExecutor(jobs) as pool:
        for name in pool.map(lambda a: run(clone, work, *a), tasks):
            print(name, flush=True)
