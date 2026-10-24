"""Ablations of nkremerh/sugarscape's departures from the text, on Figs III-1 and III-3 (book map), to find what lifts
its III-1 level above ours under the same rule S. Each variant is a patched copy of the clone (exact edits, each
required to match once); run.py runs it unchanged otherwise.
  ownsite:   rule M may choose the agent's own site, which wins ties as the nearest (p.25); the repository considers
             it only when no other site in range is open.
  nobirth:   a newborn doesn't harvest its birth site on arrival.
  sexages:   a child draws its fertility ages from its own sex's range (as our model and the text's founders do);
             the repository copies each from a random parent, so a daughter may get a father's later end.
  both:      ownsite and nobirth together; all: the three together.
Diagnostic only.

Usage: ablate.py <clone of nkremerh/sugarscape> <work folder> [seeds] [jobs] [variant,...]
"""
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import run as R

OWNSITE = [
    ("agent.py", "        cellsInRange = list(self.cellsInRange.items())\n",
     "        cellsInRange = list(self.cellsInRange.items()) + [(self.cell, 0)]\n"),
    ("agent.py", "            prey = cell.agent\n            if cell.isOccupied() and self.isNeighborValidPrey(prey) == False:\n",
     "            prey = cell.agent if cell.agent != self else None\n"
     "            if prey != None and self.isNeighborValidPrey(prey) == False:\n"),
]
NOBIRTH = [("agent.py", "        child.collectResourcesAtCell()\n", "")]
SEXAGES = [
    ("agent.py", '        childEndowment["immuneSystem"] = childImmuneSystem\n        random.setstate(randomNumberReset)\n',
     '        childEndowment["immuneSystem"] = childImmuneSystem\n'
     '        conf = self.cell.environment.sugarscape.configuration\n'
     '        prefix = "agentFemale" if childEndowment["sex"] == "female" else "agentMale"\n'
     '        childEndowment["fertilityAge"] = random.randint(*conf[prefix + "FertilityAge"])\n'
     '        childEndowment["infertilityAge"] = random.randint(*conf[prefix + "InfertilityAge"])\n'
     '        random.setstate(randomNumberReset)\n'),
]
VARIANTS = {"base": [], "ownsite": OWNSITE, "nobirth": NOBIRTH, "sexages": SEXAGES, "both": OWNSITE + NOBIRTH,
            "all": OWNSITE + NOBIRTH + SEXAGES}


def patched(clone, work, name):
    dest = work / "variants" / name
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(clone, dest, ignore=shutil.ignore_patterns(".git"))
    for file, old, new in VARIANTS[name]:
        path = dest / file
        text = path.read_text(encoding="utf-8")
        if text.count(old) != 1:
            raise SystemExit(f"{name}: expected one {old!r} in {file}, found {text.count(old)}")
        path.write_text(text.replace(old, new), encoding="utf-8")
    return dest


if __name__ == "__main__":
    clone, work = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    seeds = int(sys.argv[3]) if len(sys.argv) > 3 else 10
    jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    chosen = sys.argv[5].split(",") if len(sys.argv) > 5 else list(VARIANTS)
    copies = {v: patched(clone, work, v) for v in chosen}
    for v in chosen:
        for sub in ("logs", "conf", "runs"):
            (work / v / sub).mkdir(parents=True, exist_ok=True)
        R.book_map(work / v / "book-map.json")
    tasks = [(v, f, s) for v in chosen for f in ("1", "3") for s in range(1, seeds + 1)]
    with ThreadPoolExecutor(jobs) as pool:
        for name in pool.map(lambda a: R.run(copies[a[0]], work / a[0], a[1], "book", a[2]), tasks):
            print(name, flush=True)
