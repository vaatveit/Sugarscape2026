"""Does the long-run population depend on the starting population? (NEO config, vision 1-5)."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys
from sugarscape.config import Config
from sugarscape.model import Model
from experiments.registry import NEO

for trade in (True, False):
    for n0 in (100, 200, 400, 800):
        finals = []
        at50 = []
        for seed in range(3):
            m = Model(Config(**{**NEO, "trade": trade, "initial_population": n0}, seed=seed))
            m.run(50)
            at50.append(len(m.agents))
            m.run(450)
            finals.append(len(m.agents))
        print(f"trade={trade!s:5} n0={n0:4}  pop@50={at50}  pop@500={finals}  survivors/n0={sum(finals)/3/n0:.2f}")
