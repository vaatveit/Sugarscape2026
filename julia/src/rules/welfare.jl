# The agent welfare function and marginal rate of substitution (Chapter IV, pp.97-104, 124;
# sugarscape/rules/welfare.py).

"""
f in eq. 5: the share of the agent's tags that are 0 when preferences are cultural (p.124); 0.5 otherwise, which
reduces eq. 5 to eq. 1.
"""
function preference_fraction(a::Agent, cultural::Bool)
    (!cultural || a.ntags == 0) && return 0.5
    return (a.ntags - count_ones(a.tags)) / a.ntags
end

"""
    welfare(a, w1, w2, cultural=false)

W(w1, w2) = w1^(m1 f / mu) * w2^(m2 (1 - f) / mu), mu = m1 f + m2 (1 - f) (eqs. 1 and 5). Holdings below 0 count as
0 (eq. 6's convention); a zero exponent makes that factor 1. m1 includes the disease fees (sugar_burn).
"""
function welfare(a::Agent, w1::Real, w2::Real, cultural::Bool=false)
    f = preference_fraction(a, cultural)
    a1, a2 = sugar_burn(a) * f, a.spice_metabolism * (1 - f)
    mu = a1 + a2
    w1, w2 = max(Float64(w1), 0.0), max(Float64(w2), 0.0)
    left = a1 != 0 ? w1^(a1 / mu) : 1.0
    right = a2 != 0 ? w2^(a2 / mu) : 1.0
    return left * right
end

"""
    mrs(a, cultural=false)

Spice the agent would give for one sugar: (w2 / (m2 (1-f))) / (w1 / (m1 f)) (eq. 3; eq. 5 form). 0.0 or Inf when a
holding or a preference weight is zero; NaN when undefined.
"""
function mrs(a::Agent, cultural::Bool=false)
    f = preference_fraction(a, cultural)
    a1, a2 = sugar_burn(a) * f, a.spice_metabolism * (1 - f)
    w1, w2 = max(a.sugar, 0.0), max(a.spice, 0.0)
    numerator = a2 == 0 ? Inf : w2 / a2
    denominator = a1 == 0 ? Inf : w1 / a1
    denominator == 0 && return numerator > 0 ? Inf : NaN
    isinf(denominator) && return isfinite(numerator) ? 0.0 : NaN
    return numerator / denominator
end

"""
    SiteWelfare(m, a)

`welfare_score` for one agent's move, with the agent's part computed once: the exponents and the holdings as if phi
periods ahead. `score(sw, ls, i, j)` gives exactly welfare_score's value. A site with no sugar and no spice scores the
holdings alone (base + 0/devalue == base), cached as `w0`.
"""
struct SiteWelfare
    e1::Float64
    e2::Float64
    use1::Bool  # a zero exponent makes that factor 1 (welfare)
    use2::Bool
    base1::Float64
    base2::Float64
    w0::Float64
end

function SiteWelfare(m::Model, a::Agent)
    f = preference_fraction(a, m.config.cultural_preferences)
    a1, a2 = sugar_burn(a) * f, a.spice_metabolism * (1 - f)
    mu = a1 + a2
    phi = a.foresight
    base1 = max(a.sugar - phi * sugar_burn(a), 0.0)
    base2 = max(a.spice - phi * a.spice_metabolism, 0.0)
    e1, e2 = a1 != 0 ? a1 / mu : 0.0, a2 != 0 ? a2 / mu : 0.0
    w0 = (a1 != 0 ? base1^e1 : 1.0) * (a2 != 0 ? base2^e2 : 1.0)
    return SiteWelfare(e1, e2, a1 != 0, a2 != 0, base1, base2, w0)
end

const NO_WELFARE = SiteWelfare(0.0, 0.0, false, false, 0.0, 0.0, 1.0)  # sugar-only moves

@inline function score(sw::SiteWelfare, ls::Landscape, i::Int, j::Int)
    s, p = @inbounds ls.sugar[i, j], ls.spice[i, j]
    (s == 0 && p == 0) && return sw.w0
    devalue = 1.0 + @inbounds ls.pollution[i, j]
    left = sw.use1 ? (sw.base1 + s / devalue)^sw.e1 : 1.0
    right = sw.use2 ? (sw.base2 + p / devalue)^sw.e2 : 1.0
    return left * right
end

"""
    welfare_score(m, a, i, j)

The two-commodity score of site [i, j]: W(w1 + sugar, w2 + spice) (App. B), evaluated as if phi periods ahead (eq. 6:
holdings reduced by phi * metabolism). Pollution devalues the site's resources, x / (1 + pollution), as in the
one-commodity rule (p.47 fn 37).
"""
function welfare_score(m::Model, a::Agent, i::Int, j::Int)
    ls = m.landscape
    phi = a.foresight
    base1 = max(a.sugar - phi * sugar_burn(a), 0.0)
    base2 = max(a.spice - phi * a.spice_metabolism, 0.0)
    devalue = 1.0 + ls.pollution[i, j]
    return welfare(
        a,
        base1 + ls.sugar[i, j] / devalue,
        base2 + ls.spice[i, j] / devalue,
        m.config.cultural_preferences,
    )
end
