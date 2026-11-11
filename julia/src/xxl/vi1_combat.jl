# xxl (stage 8): VI-1-combat, the experiment of the VI-1 combat design (docs/superpowers/specs/2026-11-08-vi1-combat-design.md,
# "The experiment"). VI-1 with rule C at alpha = Inf in place of the movement rule: the attacker takes all the victim's
# sugar and spice. It is not in the registry; the combat study builds it here, so that COMBAT_EXPS (the combat report's set)
# stays as it was.

const VI1_COMBAT_ID = "VI-1-combat"
const VI1_COMBAT_VARIANT = "variant: VI-1-combat combat_alpha=Inf (attacker takes all sugar and spice)\n"

"""`text` with the variant line appended, a final newline added first when it lacks one."""
vi1_combat_text(text::AbstractString) = (endswith(text, "\n") ? text : text * "\n") * VI1_COMBAT_VARIANT

"""
    vi1_combat_experiment(reg=load_registry()) -> Experiment

VI-1 from `reg` as `VI-1-combat`: rules `({G1}, {C_∞, S, K, T, L10,10, E})`, VI-1's steps and seeds, `combat_alpha = Inf` in
both configs, and the variant line appended to both fingerprints.
"""
function vi1_combat_experiment(reg=load_registry())
    vi1 = find_experiment(reg, "VI-1")
    return Experiment(
        VI1_COMBAT_ID,
        "combat: " * vi1.title,
        "({G1}, {C_∞, S, K, T, L10,10, E})",
        vi1.steps,
        vi1.seeds,
        replace_config(vi1.config; combat_alpha=Inf),
        vi1_combat_text(vi1.fingerprint),
        replace_config(vi1.xl_config; combat_alpha=Inf),
        vi1_combat_text(vi1.xl_fingerprint),
    )
end

# VI-1-distance (docs/superpowers/specs/2026-11-09-vi1-distance-design.md): VI-1-combat with fight and fear drawn on
# cultural distance, p = h d / L with h = combat_hostility = 0.5. Built from VI-1-combat here, like it.

const VI1_DISTANCE_ID = "VI-1-distance"
const VI1_DISTANCE_VARIANT = "variant: VI-1-distance combat_hostility=0.5 (fight and fear drawn on cultural distance)\n"

"""
    vi1_distance_experiment(reg=load_registry()) -> Experiment

VI-1-combat from `reg` as `VI-1-distance`: `combat_hostility = 0.5` in both configs, and the variant line appended to both
fingerprints (VI-1-combat's, then this one).
"""
function vi1_distance_experiment(reg=load_registry())
    c = vi1_combat_experiment(reg)
    return Experiment(
        VI1_DISTANCE_ID,
        c.title,
        c.rules,
        c.steps,
        c.seeds,
        replace_config(c.config; combat_hostility=0.5),
        c.fingerprint * VI1_DISTANCE_VARIANT,
        replace_config(c.xl_config; combat_hostility=0.5),
        c.xl_fingerprint * VI1_DISTANCE_VARIANT,
    )
end

# VI-1-near, VI-1-far and VI-1-far-speed (docs/superpowers/plans/2026-11-09-vi1-reach.md): VI-1-distance with combat's or
# culture's reach changed, so that the two reaches match. Built from VI-1-distance here, like it.

const VI1_NEAR_ID = "VI-1-near"
const VI1_FAR_ID = "VI-1-far"
const VI1_FAR_SPEED_ID = "VI-1-far-speed"
const VI1_NEAR_VARIANT = "variant: VI-1-near combat_reach=neighbours (attack, fear and movement within culture's reach)
"
const VI1_FAR_VARIANT = "variant: VI-1-far culture_reach=sight (culture reaches everyone combat sees)
"
const VI1_FAR_SPEED_VARIANT = "variant: VI-1-far-speed culture_reach=attack (culture reaches everyone within speed)
"

# VI-1-distance under `id` with `change` applied to both configs and `variant` appended to both fingerprints.
function vi1_reach_experiment(reg, id::String, variant::String, change)
    d = vi1_distance_experiment(reg)
    return Experiment(
        id, d.title, d.rules, d.steps, d.seeds,
        change(d.config), d.fingerprint * variant,
        change(d.xl_config), d.xl_fingerprint * variant,
    )
end

"""
    vi1_near_experiment(reg=load_registry()) -> Experiment

VI-1-distance from `reg` as `VI-1-near`: `combat_reach = "neighbours"` in both configs (attack, fear and movement within
culture's reach), and the variant line appended to both fingerprints.
"""
vi1_near_experiment(reg=load_registry()) =
    vi1_reach_experiment(reg, VI1_NEAR_ID, VI1_NEAR_VARIANT, c -> replace_config(c; combat_reach="neighbours"))

"""
    vi1_far_experiment(reg=load_registry()) -> Experiment

VI-1-distance from `reg` as `VI-1-far`: `culture_reach = "sight"` in both configs (culture reaches everyone combat sees),
and the variant line appended to both fingerprints.
"""
vi1_far_experiment(reg=load_registry()) =
    vi1_reach_experiment(reg, VI1_FAR_ID, VI1_FAR_VARIANT, c -> replace_config(c; culture_reach="sight"))

"""
    vi1_far_speed_experiment(reg=load_registry()) -> Experiment

VI-1-distance from `reg` as `VI-1-far-speed`: `culture_reach = "attack"` (culture reaches everyone within speed) in both
configs, and the variant line appended to both fingerprints. `"attack"` needs xxl speed, which the book's and xl's configs
lack, so they are built unchecked (`unchecked_config`) and only today's xxl, where `to_xxl` adds the speed, is valid;
[`combat_plan`](@ref) and [`combat_study_args`](@ref) refuse the other worlds.
"""
vi1_far_speed_experiment(reg=load_registry()) =
    vi1_reach_experiment(reg, VI1_FAR_SPEED_ID, VI1_FAR_SPEED_VARIANT, c -> unchecked_config(c; culture_reach="attack"))

# VI-1-assim and VI-1-assim-random (docs/superpowers/plans/2026-11-09-assimilation-distance.md): VI-1-distance with rule K
# by cultural distance, so that the chance to copy is 1 - the fight chance. Built from VI-1-distance here, like it.

const VI1_ASSIM_ID = "VI-1-assim"
const VI1_ASSIM_RANDOM_ID = "VI-1-assim-random"
const VI1_ASSIM_K4_ID = "VI-1-assim-k4"
const VI1_ASSIM_VARIANT = "variant: VI-1-assim culture_rule=distance (copy a differing tag with p = 1 - fight chance)
"
const VI1_ASSIM_RANDOM_VARIANT = "variant: VI-1-assim-random culture_rule=distance-random (copy a random tag with p = 1 - fight chance)
"
const VI1_ASSIM_K4_VARIANT = "variant: VI-1-assim-k4 culture_rule=distance combat_curve=4 (copy a differing tag with p = 1 - 0.5 (d/11)^4)
"

"""
    vi1_assim_experiment(reg=load_registry()) -> Experiment

VI-1-distance from `reg` as `VI-1-assim`: `culture_rule = "distance"` in both configs (a contact copies, with probability
1 - the fight chance, one differing tag), and the variant line appended to both fingerprints.
"""
vi1_assim_experiment(reg=load_registry()) =
    vi1_reach_experiment(reg, VI1_ASSIM_ID, VI1_ASSIM_VARIANT, c -> replace_config(c; culture_rule="distance"))

"""
    vi1_assim_random_experiment(reg=load_registry()) -> Experiment

VI-1-distance from `reg` as `VI-1-assim-random`: `culture_rule = "distance-random"` in both configs (a contact copies,
with probability 1 - the fight chance, a random tag as today), and the variant line appended to both fingerprints.
"""
vi1_assim_random_experiment(reg=load_registry()) =
    vi1_reach_experiment(reg, VI1_ASSIM_RANDOM_ID, VI1_ASSIM_RANDOM_VARIANT, c -> replace_config(c; culture_rule="distance-random"))

"""
    vi1_assim_k4_experiment(reg=load_registry()) -> Experiment

VI-1-distance from `reg` as `VI-1-assim-k4`: VI-1-assim with `combat_curve = 4` in both configs, so p(fight) =
0.5 (d/11)^4 and p(copy) = 1 - p(fight), and the variant line appended to both fingerprints. The setting the 11-09
sweep picked (form A, k = 4, h = 0.5): all three bars passed on seeds 0-19 in today's xxl.
"""
vi1_assim_k4_experiment(reg=load_registry()) =
    vi1_reach_experiment(reg, VI1_ASSIM_K4_ID, VI1_ASSIM_K4_VARIANT,
        c -> replace_config(c; culture_rule="distance", combat_curve=4.0))

# VI-1-pollution and VI-1-pollution-t0 (docs/superpowers/specs/2026-11-11-vi1-pollution-design.md, "The experiments"):
# VI-1-assim-k4 with pollution and diffusion on, over 600 periods. Pollution starts on a settled society (period 350) and
# diffusion after it (period 450); the -t0 variant has both from period 0.

const VI1_POLLUTION_ID = "VI-1-pollution"
const VI1_POLLUTION_T0_ID = "VI-1-pollution-t0"
const VI1_POLLUTION_STEPS = 600
const VI1_POLLUTION_VARIANT = "variant: VI-1-pollution pollution=(1,1) pollution_start=350 diffusion_period=1 diffusion_start=450 steps=600 (pollution on a settled society, then diffusion)
"
const VI1_POLLUTION_T0_VARIANT = "variant: VI-1-pollution-t0 pollution=(1,1) pollution_start=0 diffusion_period=1 diffusion_start=0 steps=600 (pollution and diffusion from period 0)
"

# VI-1-assim-k4 under `id`, over 600 periods, with pollution (1, 1) from `pollution_start` and diffusion every period from
# `diffusion_start` set in both configs, and `variant` appended to both fingerprints.
function vi1_pollution_build(reg, id::String, variant::String, pollution_start::Int, diffusion_start::Int)
    k4 = vi1_assim_k4_experiment(reg)
    change(c) = replace_config(c; pollution=(1.0, 1.0), pollution_start=pollution_start,
                               diffusion_period=1, diffusion_start=diffusion_start)
    return Experiment(
        id, k4.title, k4.rules, VI1_POLLUTION_STEPS, k4.seeds,
        change(k4.config), k4.fingerprint * variant,
        change(k4.xl_config), k4.xl_fingerprint * variant,
    )
end

"""
    vi1_pollution_experiment(reg=load_registry()) -> Experiment

VI-1-assim-k4 from `reg` as `VI-1-pollution`: 600 periods, pollution (1, 1) from period 350 (on a settled society) and
diffusion every period from period 450, in both configs, and the variant line appended to both fingerprints.
"""
vi1_pollution_experiment(reg=load_registry()) =
    vi1_pollution_build(reg, VI1_POLLUTION_ID, VI1_POLLUTION_VARIANT, 350, 450)

"""
    vi1_pollution_t0_experiment(reg=load_registry()) -> Experiment

VI-1-assim-k4 from `reg` as `VI-1-pollution-t0`: as [`vi1_pollution_experiment`](@ref) with pollution and diffusion both on
from period 0.
"""
vi1_pollution_t0_experiment(reg=load_registry()) =
    vi1_pollution_build(reg, VI1_POLLUTION_T0_ID, VI1_POLLUTION_T0_VARIANT, 0, 0)
