# Writes the golden runs that pin the first xxl rules (XXL_V1): seven configurations, seed index 0, 25 periods each,
# one CSV per run in julia/test/fixtures/xxl-v1/. test_xxl_v1_golden.jl reruns them and compares byte for byte.
#   julia --project=julia julia/test/fixtures/make_xxl_v1_golden.jl
using Sugarscape

const GOLDEN_PERIODS = 25
const GOLDEN_DIR = joinpath(@__DIR__, "xxl-v1")

"""
    golden_cases(reg) -> Vector{Tuple{String,Experiment,XxlRules}}

(fixture name, experiment cut to `GOLDEN_PERIODS` periods, rules): four experiments under the first rules, then three
of the experiment table's rule sets on their bases, which take other code paths (round vision with no speed, speed
without a travel cost, the generated map).
"""
function golden_cases(reg)
    cut(e) = Experiment(
        e.id,
        e.title,
        e.rules,
        GOLDEN_PERIODS,
        e.seeds,
        e.config,
        e.fingerprint,
        e.xl_config,
        e.xl_fingerprint,
    )
    cases = Tuple{String,Experiment,XxlRules}[]
    for id in ("II-4", "IV-A3", "VI-1", "III-9")
        push!(cases, (id, cut(find_experiment(reg, id)), XXL_V1))
    end
    for id in ("XXL-vision", "XXL-speed/c0", "XXL-terrain/IV-A3")
        exp, rules = Sugarscape.xxl_experiment(reg, id)
        push!(cases, (replace(id, "/" => "_"), cut(exp), rules))
    end
    return cases
end

"Writes the case's seed-0 run to `path` as `write_seed_csv` does for a result."
function write_golden(path, exp, rules)
    rows, _ = Sugarscape.timed_seed(exp, 0; xxl=rules)
    columns = metric_columns(to_xxl(exp.config, rules))
    Sugarscape.write_seed_csv(path, rows; columns=columns)
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    mkpath(GOLDEN_DIR)
    for (name, exp, rules) in golden_cases(load_registry())
        write_golden(joinpath(GOLDEN_DIR, name * ".csv"), exp, rules)
        println("wrote ", name)
    end
end
