# xxl: the reduction guard. Every xxl setting at its book value is the xl run, bit for bit; each later task re-runs this.
using Sugarscape, Test

@testset "book settings are the xl run" begin
    reg = load_registry()
    for id in ("II-4", "IV-A3", "III-1", "III-9", "VI-1")
        xl = to_xl(find_experiment(reg, id).config)
        a = Model(xl)
        b = Model(replace_config(xl; xxl=XXL_BOOK))
        same = isequal(collect_metrics(a), collect_metrics(b))
        for _ in 1:50
            step!(a)
            step!(b)
            same &= isequal(collect_metrics(a), collect_metrics(b))
        end
        @test same
    end
end
