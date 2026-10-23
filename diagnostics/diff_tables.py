"""Row-by-row diff of a record's results table against a new report: changed status or observed value."""
import sys
sys.stdout.reconfigure(encoding="utf-8")  # target names use ≈


def rows(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 8 and cells[0] not in ("Experiment", "---") and not cells[0].startswith("-"):
            out[(cells[0], cells[1])] = (cells[5], cells[7])
    return out


old, new = rows(sys.argv[1]), rows(sys.argv[2])
for k in new:
    if k not in old:
        print("NEW ", k, new[k])
    elif old[k] != new[k]:
        print(f"{old[k][1]:>5} -> {new[k][1]:<5} {k[0]} | {k[1]} | {old[k][0]} -> {new[k][0]}")
for k in old:
    if k not in new:
        print("GONE", k)
