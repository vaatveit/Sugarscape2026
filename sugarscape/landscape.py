"""The sugarscape lattice: resource levels, capacities, pollution, and site rules."""

import numpy as np


class Landscape:
    """A torus of sites indexed [x, y] (x east, y north, y = 0 the southern row)."""

    def __init__(self, capacity: np.ndarray) -> None:
        self.capacity = np.asarray(capacity, dtype=int).copy()
        self.width, self.height = self.capacity.shape
        # p.21: "the sugar level at every site initially at its capacity value".
        self.sugar = self.capacity.astype(float)
        self.pollution = np.zeros(self.capacity.shape, dtype=float)

    def wrap(self, x: int, y: int) -> tuple[int, int]:
        return x % self.width, y % self.height

    def growback(self, rate: float) -> None:
        """G_alpha (p.23 fn 3): r(t+1) = min(r(t) + alpha, c); alpha = inf gives G_inf (p.26)."""
        np.minimum(self.sugar + rate, self.capacity, out=self.sugar)

    def is_summer_north(self, t: int, gamma: int) -> bool:
        """p.44 fn 33: the top half is in summer while (t mod 2*gamma) / gamma < 1."""
        return (t % (2 * gamma)) < gamma

    def seasonal_growback(self, t: int, alpha: float, beta: int, gamma: int) -> None:
        """S_alpha,beta,gamma (p.44): summer grows alpha per period; winter alpha per beta periods.

        Winter is read literally: alpha is added on periods where t % beta == 0 (our call;
        the alternative is alpha/beta every period).
        """
        north = np.zeros(self.capacity.shape, dtype=bool)
        north[:, self.height // 2 :] = True
        summer = north if self.is_summer_north(t, gamma) else ~north
        rate = np.where(summer, alpha, alpha if t % beta == 0 else 0.0)
        np.minimum(self.sugar + rate, self.capacity, out=self.sugar)

    def diffuse(self) -> None:
        """D_alpha (p.48): each site's new pollution is the mean over its von Neumann neighbors."""
        p = self.pollution
        flux = (
            np.roll(p, 1, axis=0) + np.roll(p, -1, axis=0) + np.roll(p, 1, axis=1) + np.roll(p, -1, axis=1)
        ) / 4.0
        self.pollution = flux
