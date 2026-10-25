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

"""Equal up to float rounding: how cross-language fixtures compare amounts."""
near(a, b) = isapprox(a, b; rtol=1e-12, atol=1e-9)

"""A 0/1 vector as the bit field the Agent stores (bit i-1 is position i)."""
function bits(v)
    return foldl(
        (acc, (i, b)) -> acc | (UInt64(b) << (i - 1)), enumerate(v); init=UInt64(0)
    )
end

"""The agent's tags as a 0/1 vector."""
tags_of(a) = [Int((a.tags >> (i - 1)) & 1) for i in 1:(a.ntags)]

function tag!(a, v)
    a.tags, a.ntags = bits(v), length(v)
    return a
end

"""A free-standing tagged agent, on no grid (make_tagged)."""
loose(v...) = tag!(Agent(10_000, 0, 0, 1, 1, 10.0), collect(v))

"""A fertile couple at (2, 2) and (2, 3), endowed with 60 (conftest.couple)."""
function couple(m; sugar=60.0)
    f = put_agent(m, 2, 2; sugar=sugar)
    f.sex, f.fertility_start, f.fertility_end, f.initial_sugar = :F, 12, 40, 60.0
    h = put_agent(m, 2, 3; sugar=sugar)
    h.sex, h.fertility_start, h.fertility_end, h.initial_sugar = :M, 12, 50, 60.0
    f.age = h.age = 20
    return f, h
end
