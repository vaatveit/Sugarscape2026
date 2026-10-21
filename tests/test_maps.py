import numpy as np

from sugarscape.maps import load_map


def test_shape_and_range():
    m = load_map("sugar-map.txt")
    assert m.shape == (50, 50)
    assert m.min() == 0 and m.max() == 4


def test_peaks_are_northeast_and_southwest():  # Fig II-1, p.21
    m = load_map("sugar-map.txt")
    xs, ys = np.nonzero(m == 4)
    ne = (xs >= 25) & (ys >= 25)
    sw = (xs < 25) & (ys < 25)
    assert ne.any() and sw.any()
    assert (ne | sw).all()  # no level-4 cells in NW or SE
