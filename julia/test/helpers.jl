# Helpers for building small, hand-specified models in tests (tests/conftest.py in Julia).
using Sugarscape

"""A model on an explicit capacity grid (indexed [x + 1, y + 1]) with no initial agents."""
function tiny_model(capacity::AbstractMatrix{<:Integer}; kw...)
    base = (;
        width=size(capacity, 1),
        height=size(capacity, 2),
        initial_population=0,
        vision=(1, 1),
    )
    cfg = replace_config(Config(); merge(base, values(kw))...)
    return Model(cfg; capacity=Matrix{Int}(capacity))
end

function put_agent(m, x, y; vision=1, metabolism=1, sugar=10.0, max_age=Inf)
    return new_agent!(m, x, y, vision, metabolism, sugar; max_age=max_age)
end
