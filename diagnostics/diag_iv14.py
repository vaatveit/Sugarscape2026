"""IV-14 die-off: births, deaths by cause, and which fertility test binds."""
from _pin import pin
pin("A")  # defaults this diagnostic was written under; see _pin.py
import sys
from collections import Counter
from experiments.registry import EXPERIMENTS
from sugarscape.model import Model
from sugarscape.rules import sex

for exp_id in ("IV-14", "IV-18"):
    cfg = EXPERIMENTS[exp_id].config
    m = Model(cfg)
    orig_die = m.die
    deaths = Counter()

    def die(agent, excluded_heirs=(), m=m, deaths=deaths):
        if agent.age >= agent.max_age:
            cause = "age"
        elif agent.sugar <= 0:
            cause = "sugar"
        elif agent.spice <= 0:
            cause = "spice"
        else:
            cause = "other"
        deaths[(m.t // 25, cause, "founder" if agent.id < cfg.initial_population else "child")] += 1
        orig_die(agent, excluded_heirs)

    m.die = die
    print(f"== {exp_id}")
    for t in range(200):
        n_before = len(m.agents)
        fert_age = [a for a in m.agents if a.fertility_start <= a.age < a.fertility_end]
        sugar_ok = sum(a.sugar >= a.initial_sugar for a in fert_age)
        both_ok = sum(sex.is_fertile(a) for a in fert_age)
        children = sum(1 for a in m.agents if a.id >= cfg.initial_population)
        m.step()
        if t % 25 == 0 or t in (12, 60, 75):
            print(f"t={t:3} pop={n_before:3} children={children:3} fertile-age={len(fert_age):3} "
                  f"sugar>=init={sugar_ok:3} both>=init={both_ok:3}")
    print("deaths by (25-period block, cause, who):")
    for k in sorted(deaths):
        print("  ", k, deaths[k])
