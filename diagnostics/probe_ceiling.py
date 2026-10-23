"""Net income per agent vs N for evolved agents (metabolism 1, vision 1-6 and 5-6, immortal, rich), t=50-200,
and the share with negative net income; total regrowth ceiling for reference."""
from _pin import pin
pin("C")  # defaults this diagnostic was written under; see _pin.py
from concurrent.futures import ProcessPoolExecutor
import numpy as np
from sugarscape.config import Config
from sugarscape.model import Model


def income(args):
    n, vis, seed = args
    m = Model(Config(initial_population=n, vision=vis, metabolism=(1, 1), endowment=(1000, 1000), seed=seed))
    net, neg = [], []
    for t in range(200):
        m.step()
        if t >= 50:
            x = np.array([a.last_income for a in m.agents]); net.append(x.mean()); neg.append((x < 0).mean())
    return n, vis, np.mean(net), np.mean(neg)


if __name__ == "__main__":
    tasks = [(n, v, s) for n in (1000, 1200, 1400, 1600, 1800, 2000) for v in ((1, 6), (5, 6)) for s in range(2)]
    with ProcessPoolExecutor(8) as pool:
        res = list(pool.map(income, tasks))
    m = Model(Config())
    print("sites with capacity >= 1:", int((m.landscape.capacity >= 1).sum()))
    for n in (1000, 1200, 1400, 1600, 1800, 2000):
        for v in ((1, 6), (5, 6)):
            r = [x for x in res if x[0] == n and x[1] == v]
            print(f"N={n} vision {v}: net income {np.mean([x[2] for x in r]):+.2f}, share losing sugar in a period {np.mean([x[3] for x in r]):.2f}")
