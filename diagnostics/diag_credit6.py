"""Why so few loans in VI-1? Count credit seekers and why they fail."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
from collections import Counter
from dataclasses import replace
import sugarscape.rules.credit as credit
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model

c = Counter()
orig = credit.seek_credit
def counting(model, agent):
    need = credit.shortfall(model, agent)
    if need > 0:
        c["seekers"] += 1
        lenders = [n for n in model.neighbors_of(agent) if credit.available_to_lend(model, n) > 0]
        if not lenders:
            c["no lender neighbor"] += 1
        else:
            c["has lender"] += 1
            amt = min(credit.available_to_lend(model, lenders[0]), need)
            if not credit.creditworthy(model, agent, credit._amount_due(model, amt)):
                c["not creditworthy"] += 1
            c["income<=0"] += agent.last_income <= 0
    return orig(model, agent)

credit.seek_credit = counting
for seed in range(3):
    m = Model(replace(EXPERIMENTS["VI-1"].config, seed=seed))
    m.run(120)
print(dict(c))
