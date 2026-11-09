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
