from importlib import resources

import numpy as np

from sugarscape.maps import load_map, parse_map
from sugarscape.maps.xl import XL_MAP, blurred_levels, map_text, upscale

BASE = load_map("sugar-map.txt")


def test_committed_map_is_the_generator_output():
    committed = resources.files("sugarscape.maps").joinpath(XL_MAP).read_text()
    assert committed == map_text(upscale(BASE))


def test_xl_map_loads_as_500_by_500_levels_0_to_4():
    m = load_map(XL_MAP)
    assert m.shape == (500, 500) and m.min() == 0 and m.max() == 4


def test_map_text_round_trips_orientation():
    a = np.arange(6).reshape(3, 2) % 5  # [x, y], not symmetric
    assert np.array_equal(parse_map(map_text(a)), a)


def test_every_10x10_block_keeps_its_original_value():
    fine = load_map(XL_MAP)
    blocks = fine.reshape(50, 10, 50, 10).transpose(0, 2, 1, 3).reshape(50, 50, 100)
    assert np.array_equal(fine[5::10, 5::10], BASE)  # block centres
    majority = np.apply_along_axis(lambda b: np.bincount(b, minlength=5).argmax(), 2, blocks)
    assert np.array_equal(majority, BASE)


def test_terrace_areas_are_100x_to_within_1_1_percent():
    fine = load_map(XL_MAP)
    ratios = [(fine == v).sum() / (100 * (BASE == v).sum()) for v in range(5)]
    assert [round(r, 4) for r in ratios] == [0.9985, 0.9992, 1.0028, 1.0024, 0.9893]
    assert all(abs(r - 1) <= 0.011 for r in ratios)


def test_no_cell_is_near_the_threshold():
    # 3.4e-4 measured; far above float64 rounding, so the file regenerates identically on any machine
    assert min(float(np.abs(b).min()) for b in blurred_levels(BASE)) > 1e-4


def test_upscaling_commutes_with_the_spice_mirror():
    assert np.array_equal(upscale(BASE[::-1, :]), upscale(BASE)[::-1, :])
