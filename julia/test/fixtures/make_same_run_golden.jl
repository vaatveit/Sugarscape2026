# Writes the digests that pin runs to the bit while their hot paths are made faster: one seed for SAME_RUN_PERIODS periods
# under each of the rule settings that take a different path through them, book rules included. Each digest covers every
# period's metrics, to the bit, and the random stream where it ends. test_xxl_same_run.jl reruns them.
#   julia --project=julia julia/test/fixtures/make_same_run_golden.jl
using Sugarscape

const SAME_RUN_PERIODS = 100
const SAME_RUN_FILE = joinpath(@__DIR__, "same-run-digests.txt")

"""(fixture name, config) for each run. Long enough for founders to die of old age with loans on the book."""
function same_run_cases(reg)
    vi1, ii4 = find_experiment(reg, "VI-1").config, find_experiment(reg, "II-4").config
    iii9 = find_experiment(reg, "III-9").config
    rules(; kw...) = replace_rules(XXL_DEFAULTS; kw...)
    list_b = replace_rules(XXL_DEFAULTS; disease_count=4, founder_diseases=2, disease_lengths=(9, 10))
    defaults = to_xxl(vi1, XXL_DEFAULTS)
    return [
        ("defaults", replace_config(defaults; seed=defaults.seed + 30)),
        ("disease-list", replace_config(to_xxl(vi1, list_b); seed=defaults.seed + 31)),
        ("inheritance", replace_config(defaults; seed=defaults.seed + 32, inheritance=true)),
        ("claims", replace_config(defaults; seed=defaults.seed + 33, claims_outlive_lender=true)),
        ("cultural", replace_config(defaults; seed=defaults.seed + 34, cultural_preferences=true)),
        ("neighbours", replace_config(defaults; seed=defaults.seed + 35, mate_contact="neighbors")),
        ("sugar-only", replace_config(to_xxl(ii4, XXL_DEFAULTS); seed=defaults.seed + 36)),
        ("radius-1", replace_config(to_xxl(vi1, rules(; interaction_radius=1.0)); seed=defaults.seed + 37)),
        ("no-memory", replace_config(to_xxl(vi1, rules(; memory=0, word_of_mouth=false)); seed=defaults.seed + 38)),
        ("no-speed", replace_config(to_xxl(vi1, rules(; speed=nothing, travel_cost=0.0, memory=0, word_of_mouth=false, free_step=0.0)); seed=defaults.seed + 39)),
        ("lattice", replace_config(to_xxl(vi1, rules(; vision_shape="lattice")); seed=defaults.seed + 40)),
        ("limits", replace_config(defaults; seed=defaults.seed + 41, lender_limit=true, credit_reach=2.0)),
        ("combat", replace_config(to_xxl(iii9, XXL_DEFAULTS); seed=defaults.seed + 42)),
        ("book-vi1", replace_config(vi1; seed=vi1.seed + 43)),
        ("book-iii9", replace_config(iii9; seed=iii9.seed + 44)),
    ]
end

"""The run's digest, and how much of what it is meant to reach it reached: (; digest, loans, dead, children)."""
function same_run_digest(cfg)
    m = Model(cfg)
    bytes = UInt8[]
    dead = 0
    for _ in 1:SAME_RUN_PERIODS
        step!(m)
        dead += deaths_this_step(m)
        append!(bytes, reinterpret(UInt8, collect_metrics(m)))
    end
    append!(bytes, reinterpret(UInt8, [rand(m.rng, UInt64)]))
    digest = bytes2hex(Sugarscape.sha256(bytes))
    return (; digest, loans=m.loans_made, dead, ever=agents_ever(m))
end

if abspath(PROGRAM_FILE) == @__FILE__
    open(SAME_RUN_FILE, "w") do io
        for (name, cfg) in same_run_cases(load_registry())
            r = same_run_digest(cfg)
            println(io, name, " ", r.digest)
            println("wrote ", name, ": ", r.loans, " loans made, ", r.dead, " deaths, ", r.ever, " agents ever")
        end
    end
end
