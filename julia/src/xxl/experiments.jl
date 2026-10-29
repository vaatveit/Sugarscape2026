# xxl: the XXL-... experiments and the xxl fingerprint (spec, "Runner and experiments"). They have no Python
# counterpart, so they are defined here rather than in the exported registry.toml: each is a registered sugarscape
# experiment passed through `to_xxl` with its own rules.

"""
    rules_line(rules) -> String

Every `XxlRules` field as `name=value`, in field order, separated by spaces. Strings print with `repr`, the rest with
`string`: `vision_shape="disc" speed=(1, 6) travel_cost=0.1 ...`.
"""
function rules_line(rules::XxlRules)
    return join(
        (
            "$f=" * (v isa AbstractString ? repr(v) : string(v)) for
            (f, v) in ((f, getfield(rules, f)) for f in fieldnames(XxlRules))
        ),
        " ",
    )
end

"""
    xxl_fingerprint(exp, rules) -> String

What a saved xxl result was produced from: `julia`, an `xxl` line with every rule (those actually applied, so a season
gradient the base experiment has no seasons for reads `false`), the base experiment's xl fingerprint, then one
`xxl map <file> sha256=<hex>` line per generated map in use (the spice map only when the config has spice). A change to
the rules, the base experiment or the maps makes saved xxl results stale.
"""
function xxl_fingerprint(exp::Experiment, rules::XxlRules)
    cfg = to_xxl(exp.config, rules)
    lines = String["julia", "xxl " * rules_line(cfg.xxl)]
    text = join(lines, "\n") * "\n" * exp.xl_fingerprint
    endswith(text, "\n") || (text *= "\n")
    maps = if xxl_on(cfg, :generated)
        (cfg.spice ? [XXL_MAP, XXL_SPICE_MAP] : [XXL_MAP])
    else
        String[]
    end
    for name in maps
        text *= "xxl map $name sha256=$(map_sha256(name))\n"
    end
    return text
end

# The spec's table: (id, base experiment id, rules). Every field not named stays at its book setting.
disc_speed(c) = XxlRules(; vision_shape="disc", speed=(1, 6), travel_cost=c)

"The XXL experiments, in the spec's order: (id, base experiment id, rules)."
const XXL_EXPERIMENTS = Tuple{String,String,XxlRules}[
    ("XXL-vision", "II-4", XxlRules(; vision_shape="disc")),
    ("XXL-speed/c0", "II-4", disc_speed(0.0)),
    ("XXL-speed/c0.05", "II-4", disc_speed(0.05)),
    ("XXL-speed/c0.1", "II-4", disc_speed(0.1)),
    ("XXL-speed/c0.2", "II-4", disc_speed(0.2)),
    ("XXL-memory/solo", "II-4", replace_rules(disc_speed(0.1); memory=8)),
    (
        "XXL-memory/shared",
        "II-4",
        replace_rules(disc_speed(0.1); memory=8, word_of_mouth=true),
    ),
    ("XXL-radius/R1", "IV-A3", replace_rules(XXL_V1; interaction_radius=1.0)),
    ("XXL-radius/R1.5", "IV-A3", replace_rules(XXL_V1; interaction_radius=1.5)),
    ("XXL-radius/R3", "IV-A3", replace_rules(XXL_V1; interaction_radius=3.0)),
    ("XXL-seasons/halves", "II-7", replace_rules(XXL_V1; season_gradient=false)),
    ("XXL-seasons/gradient", "II-7", replace_rules(XXL_V1; season_gradient=true)),
    ("XXL-terrain/II-4", "II-4", replace_rules(XXL_V1; landscape="generated")),
    ("XXL-terrain/IV-A3", "IV-A3", replace_rules(XXL_V1; landscape="generated")),
    ("XXL-society/VI-1", "VI-1", XXL_V1),
    ("XXL-combat/III-9", "III-9", XXL_V1),
]

const XXL_SEEDS = 5  # 5 seeds each, given the cost (spec)

"""
    xxl_experiment(reg, id) -> (Experiment, XxlRules)

The XXL experiment `id` as an `Experiment` over its base: the base's steps, configs and fingerprints, five seeds, and
the base's title prefixed `xxl: `; with the rules to run it under (`run_experiment(exp; xxl=rules)`).
"""
function xxl_experiment(reg::AbstractVector{Experiment}, id::AbstractString)
    i = findfirst(e -> e[1] == id, XXL_EXPERIMENTS)
    i === nothing && throw(ArgumentError("no XXL experiment $(repr(id))"))
    _, base_id, rules = XXL_EXPERIMENTS[i]
    base = find_experiment(reg, base_id)
    exp = Experiment(
        String(id),
        "xxl: " * base.title,
        base.rules,
        base.steps,
        XXL_SEEDS,
        base.config,
        base.fingerprint,
        base.xl_config,
        base.xl_fingerprint,
    )
    return exp, rules
end

"""The XXL ids `arg` names: `"XXL"` for all of them, else an id itself or a family prefix followed by `/`."""
function xxl_matching_ids(arg::AbstractString)
    ids = [e[1] for e in XXL_EXPERIMENTS]
    arg == "XXL" && return ids
    return matching_ids(arg, ids)
end
