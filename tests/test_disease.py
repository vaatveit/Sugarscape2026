from conftest import make_tagged
from sugarscape.rules.disease import immune_response, immune_step, infect, is_immune, nearest_substring


def bits(s):
    return [int(c) for c in s]


def test_table_v1_example():  # pp.143-144
    immune = bits("1011101001")
    disease = tuple(bits("10011"))
    assert nearest_substring(immune, disease) == (0, 1)
    assert immune_step(immune, disease) is True  # one flip, at I's position 3
    assert "".join(map(str, immune)) == "1001101001"


def test_leftmost_window_wins_ties():  # fn 11
    assert nearest_substring(bits("0011"), bits("1")) == (2, 0)
    assert nearest_substring(bits("1010"), bits("01")) == (1, 0)
    assert nearest_substring(bits("0000"), bits("11")) == (0, 2)


def test_learning_takes_one_flip_per_period():
    immune = bits("0000000")
    disease = (1, 1, 1)
    assert [immune_step(immune, disease) for _ in range(3)] == [False, False, True]


def test_infect_skips_immune_and_duplicates():  # Review Focus 2
    a = make_tagged([0])
    a.immune = bits("110010")
    a.disease_fee = 1.0
    assert infect(a, (0, 1, 0)) is False and a.diseases == []  # 010 is a substring
    assert infect(a, (1, 1, 1)) is True and infect(a, (1, 1, 1)) is False
    assert a.diseases == [(1, 1, 1)] and a.sugar_burn == a.metabolism + 1.0


def test_immune_response_clears_matched_diseases():
    a = make_tagged([0])
    a.immune = bits("1011101001")
    a.diseases = [tuple(bits("10011")), (0,) * 6]  # 000000 is 3 bits from its nearest window
    immune_response(a)
    assert a.diseases == [(0,) * 6]


def test_memory_corruption_allows_reinfection():  # p.145, Review Focus 3
    a = make_tagged([0])
    a.immune = bits("110")
    assert infect(a, (0, 0)) is True
    immune_response(a)
    immune_response(a)
    assert a.diseases == [] and not is_immune(a.immune, (1, 1))
    assert infect(a, (1, 1)) is True  # 11 was unlearned
