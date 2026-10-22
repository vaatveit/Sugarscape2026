import numpy as np

from conftest import couple, put_agent, tiny_model
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.rules.disease import immune_response, is_immune, transmit
from sugarscape.rules.movement import metabolize
from sugarscape.rules.sex import mate
from sugarscape.rules.welfare import mrs


def disease_model(**kw):
    return Model(Config(disease_list=10, diseases_per_agent=4, seed=1, **kw))


def test_master_list_and_initial_infection():  # p.147
    m = disease_model()
    assert len(m.disease_list) == 10 and all(1 <= len(d) <= 10 for d in m.disease_list)
    assert all(len(a.immune) == 50 and a.immune == a.immune_genotype for a in m.agents)
    assert all(len(a.diseases) <= 4 and len(set(a.diseases)) == len(a.diseases) for a in m.agents)
    assert all(not is_immune(a.immune, d) for a in m.agents for d in a.diseases)
    assert any(a.diseases for a in m.agents) and all(a.disease_fee == 1.0 for a in m.agents)


def test_phenotype_trains_genotype_does_not():  # p.146, Review Focus 4
    m = disease_model()
    a = next(a for a in m.agents if a.diseases)
    before = list(a.immune_genotype)
    for _ in range(12):
        immune_response(a)
    assert a.immune_genotype == before and a.immune is not a.immune_genotype


def test_transmission_logs_new_infections():  # p.145, p.150
    m = tiny_model(np.ones((5, 5), dtype=int), disease_list=1, diseases_per_agent=0, disease_length=(3, 3))
    sick = put_agent(m, 2, 2)
    well = put_agent(m, 2, 3)
    for a in (sick, well):
        a.immune, a.immune_genotype, a.disease_fee = [0] * 10, [0] * 10, 1.0
    sick.diseases = [(1, 1, 1)]
    transmit(m, sick)
    assert well.diseases == [(1, 1, 1)] and m.infection_log == [(sick, well)]
    transmit(m, sick)
    assert m.infection_log == [(sick, well)]  # already carried: no new infection


def test_fee_raises_burn_and_changes_behaviour():  # p.143, Review Focus 5
    m = tiny_model(np.ones((5, 5), dtype=int), spice=True, disease_list=1, diseases_per_agent=0)
    a = put_agent(m, 2, 2, sugar=10.0)
    a.spice, a.spice_metabolism, a.disease_fee = 10.0, 1, 1.0
    healthy = mrs(a)
    a.diseases = [(1,), (0,)]
    assert a.sugar_burn == a.metabolism + 2.0 and mrs(a) > healthy
    metabolize(m, a)
    assert a.sugar == 10.0 - (a.metabolism + 2.0)


def test_children_inherit_crossed_genotype_without_diseases():  # p.146
    m = tiny_model(np.ones((6, 6), dtype=int), sex=True, disease_list=2, diseases_per_agent=0)
    f, h = couple(m)
    f.immune_genotype, h.immune_genotype = [0, 0, 1, 1] * 13, [0, 1, 0, 1] * 13
    f.immune, h.immune = list(f.immune_genotype), list(h.immune_genotype)
    f.diseases = [(1, 1)]
    child = mate(m, f)[0]
    assert child.immune_genotype[0::4] == [0] * 13 and child.immune == child.immune_genotype
    assert child.immune is not child.immune_genotype and child.diseases == []
    assert child.disease_fee == 1.0


def test_replacements_are_healthy_with_random_immunity():
    m = Model(Config(disease_list=10, diseases_per_agent=4, max_age=(1, 1), replacement=True,
                     initial_population=30, seed=3))
    m.step()
    assert all(a.diseases == [] and len(a.immune) == 50 for a in m.agents)


def test_sick_society_runs():  # smoke: no crash, deaths allowed
    m = Model(Config(disease_list=25, diseases_per_agent=10, endowment=(25, 50), seed=2))
    m.run(30)
    assert all(a.alive and len(set(a.diseases)) == len(a.diseases) for a in m.agents)
    assert all(t.alive for _, t in m.infection_log)


def test_one_bit_disease_is_passed_on_before_it_is_learned():  # p.143; design: transmission, then response
    m = tiny_model(np.ones((5, 5), dtype=int), disease_list=1, diseases_per_agent=0)
    sick = put_agent(m, 2, 2)
    well = put_agent(m, 2, 3)
    sick.immune, sick.immune_genotype = [1, 1, 0] + [0] * 7, [0] * 10
    well.immune, well.immune_genotype = [0] * 10, [0] * 10
    for a in (sick, well):
        a.disease_fee = 1.0
    sick.diseases = [(1, 1, 1)]  # one bit from sick's window 110
    m.step()
    assert sick.diseases == [] and well.diseases[:1] == [(1, 1, 1)]
