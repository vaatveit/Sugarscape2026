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
    welfare_rises(a, s1, p1, s0, p0, cultural) -> Bool

`welfare(a, s1, p1, cultural) > welfare(a, s0, p0, cultural)`, with no powers when [`surely_less`](@ref) settles it, as it
does for most offers. It can only say so of positive holdings before: a holding at or below 0 counts as 0.
"""
@inline function welfare_rises(a::Agent, s1::Float64, p1::Float64, s0::Float64, p0::Float64, cultural::Bool)
    if s0 > 0 && p0 > 0
        f = preference_fraction(a, cultural)
        a1, a2 = sugar_burn(a) * f, a.spice_metabolism * (1 - f)
        mu = a1 + a2
        c1, c2 = prune_weights(a1 / mu, a2 / mu, s0, p0)
        surely_less(c1, c2, s1, p1) && return false
    end
    return welfare(a, s1, p1, cultural) > welfare(a, s0, p0, cultural)
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
holdings alone (base + 0/devalue == base), cached as `w0`. `lambda` and `inv_p` are xxl rule 13's (see
`SiteWelfare(m, a, looked)`); both are 0 here, the book's score.
"""
struct SiteWelfare
    e1::Float64
    e2::Float64
    use1::Bool  # a zero exponent makes that factor 1 (welfare)
    use2::Bool
    base1::Float64
    base2::Float64
    w0::Float64
    lambda::Float64  # rule 13's blend: 0 is the book's welfare, 1 the value at the expected price
    inv_p::Float64  # sugar per spice at the expected price (0 with lambda 0)
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
    return SiteWelfare(e1, e2, a1 != 0, a2 != 0, base1, base2, w0, 0.0, 0.0)
end

"""
    SiteWelfare(m, a, looked)

xxl rule 13, movement that counts on trade (docs/xxl.md, "Rule 13"): the agent's part of the score for a move in which
it looked at `looked` (0-based sites, as [`look!`](@ref) gives them). Off the rule it is `SiteWelfare(m, a)`. On it, the
blend `lambda` is `trade_blend` and `inv_p` is 1 / [`expected_price`](@ref), so a bundle (A, B) scores
[`trade_value`](@ref); `lambda` stays 0, the book's score, when there is no expected price, or under the guard: the
agent's sugar or spice would last fewer than `trade_guard` periods at its metabolism. Draws nothing.
"""
function SiteWelfare(m::Model, a::Agent, looked::Vector{Tuple{Int,Int}})
    sw = SiteWelfare(m, a)
    xxl_on(m.config, :trade_move) || return sw
    r = m.config.xxl
    r.trade_blend == 0 && return sw
    k = r.trade_guard
    k !== nothing && (a.sugar < k * sugar_burn(a) || a.spice < k * a.spice_metabolism) && return sw
    p = expected_price(m, a, looked)
    isnan(p) && return sw
    return priced(sw, r.trade_blend, 1 / p)
end

"""No sites looked at: `SiteWelfare(m, a, NO_SITES)` for a move that keeps no list of its look. Never written to."""
const NO_SITES = Tuple{Int,Int}[]

# `sw` scoring at blend `lambda` and `inv_p` sugar per spice; the empty site's cached score too.
function priced(sw::SiteWelfare, lambda::Float64, inv_p::Float64)
    lambda == 0 && return sw
    w0 = trade_value(lambda, inv_p, sw.w0, sw.base1, sw.base2)
    return SiteWelfare(sw.e1, sw.e2, sw.use1, sw.use2, sw.base1, sw.base2, w0, lambda, inv_p)
end

"""
    trade_value(lambda, inv_p, w, A, B) -> Float64

Rule 13's score of a bundle of A sugar and B spice whose book welfare is `w` (= A^e1 B^e2): w^(1-λ) V^λ with
V = A + B · inv_p, its value in sugar at the expected price. Both w and V are of degree 1 in (A, B), so the blend needs
no units (our call); λ = 1 ranks by V alone. Called only with λ > 0: at 0 the book's expression is used as it stands.
"""
@inline trade_value(lambda::Float64, inv_p::Float64, w::Float64, A::Float64, B::Float64) =
    w^(1 - lambda) * (A + B * inv_p)^lambda

const NO_WELFARE = SiteWelfare(0.0, 0.0, false, false, 0.0, 0.0, 1.0, 0.0, 0.0)  # sugar-only moves

const SURELY_BELOW = 1.0 - 1e-9  # far enough under 1 that no rounding in the powers could bring the two values level

"""
    surely_less(c1, c2, A, B) -> Bool

Whether A^e1 * B^e2 is below a reference Ar^e1 * Br^e2, told without taking a power; `c1, c2 =`
[`prune_weights`](@ref)`(e1, e2, Ar, Br)`. With e1 + e2 = 1 these are weighted geometric means, so by weighted AM-GM the
first is at most (e1 A/Ar + e2 B/Br) times the second. `false` says nothing: the powers must decide. A reference of zero
makes a weight Inf, and Inf * 0 is NaN, so nothing is ruled out against it.
"""
@inline surely_less(c1::Float64, c2::Float64, A::Float64, B::Float64) = c1 * A + c2 * B < SURELY_BELOW

@inline prune_weights(e1::Float64, e2::Float64, Ar::Float64, Br::Float64) = (e1 / Ar, e2 / Br)

@inline function score(sw::SiteWelfare, ls::Landscape, i::Int, j::Int)
    s, p = @inbounds ls.sugar[i, j], ls.spice[i, j]
    (s == 0 && p == 0) && return sw.w0
    devalue = 1.0 + @inbounds ls.pollution[i, j]
    A, B = sw.base1 + s / devalue, sw.base2 + p / devalue
    left = sw.use1 ? A^sw.e1 : 1.0
    right = sw.use2 ? B^sw.e2 : 1.0
    sw.lambda == 0 && return left * right
    return trade_value(sw.lambda, sw.inv_p, left * right, A, B)
end

"""
    score(sw, ls, i, j, g1, g2)

[`score`](@ref) of site [i, j] with `g1` sugar and `g2` spice held besides, as combat's loot: the welfare of
(base1 + site sugar / devalue + g1, base2 + site spice / devalue + g2). The goods are held, not the site's, so pollution
doesn't devalue them. With g1 = g2 = 0 it is `score(sw, ls, i, j)`; the bare-site shortcut `w0` is taken only when the
site and the goods are all zero.
"""
@inline function score(sw::SiteWelfare, ls::Landscape, i::Int, j::Int, g1::Float64, g2::Float64)
    s, p = @inbounds ls.sugar[i, j], ls.spice[i, j]
    (s == 0 && p == 0 && g1 == 0 && g2 == 0) && return sw.w0
    devalue = 1.0 + @inbounds ls.pollution[i, j]
    A, B = sw.base1 + s / devalue + g1, sw.base2 + p / devalue + g2
    left = sw.use1 ? A^sw.e1 : 1.0
    right = sw.use2 ? B^sw.e2 : 1.0
    sw.lambda == 0 && return left * right
    return trade_value(sw.lambda, sw.inv_p, left * right, A, B)
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
