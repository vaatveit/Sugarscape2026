# Agent trade rule T: bilateral exchange of sugar and spice (pp.101-107, App. B p.184; sugarscape/rules/trade.py).

valid_mrs(v::Float64) = isfinite(v) && v > 0

"""
    bargain!(m, a, b)

Rule T between two neighbours (p.105). While their MRSs differ: the price is the geometric mean of the MRSs (eq. 4);
the agent with the higher MRS buys sugar with spice (p > 1: p spice for 1 sugar; p < 1: 1 spice for 1/p sugar). The
exchange happens only if both agents' welfare strictly rises and their MRSs don't cross (fn 17); otherwise
bargaining ends. An MRS of 0, infinity, or undefined means no trade (our call). trade_rounding="down" rounds the
amount of p or 1/p down to a whole unit (VAR-inttrade); the price stays p. Each exchange goes to `m.trade_log`.
"""
function bargain!(m::Model, a::Agent, b::Agent)
    cultural = m.config.cultural_preferences
    whole = m.config.trade_rounding == "down"
    while true
        ma, mb = mrs(a, cultural), mrs(b, cultural)
        (!(valid_mrs(ma) && valid_mrs(mb)) || ma == mb) && return nothing
        hi, lo = ma > mb ? (a, b) : (b, a)
        price = sqrt(ma * mb)
        sugar, spice =
            price > 1 ? (1.0, price) : (price < 1 ? (1.0 / price, 1.0) : (1.0, 1.0))
        if whole
            sugar, spice = floor(sugar), floor(spice)
        end
        old = (hi.sugar, hi.spice, lo.sugar, lo.spice)
        before_hi = welfare(hi, hi.sugar, hi.spice, cultural)
        before_lo = welfare(lo, lo.sugar, lo.spice, cultural)
        hi.sugar, hi.spice = hi.sugar + sugar, hi.spice - spice
        lo.sugar, lo.spice = lo.sugar - sugar, lo.spice + spice
        accepted =
            min(hi.sugar, hi.spice, lo.sugar, lo.spice) > 0 &&
            welfare(hi, hi.sugar, hi.spice, cultural) > before_hi &&
            welfare(lo, lo.sugar, lo.spice, cultural) > before_lo &&
            mrs(hi, cultural) >= mrs(lo, cultural)  # no crossing over
        if !accepted
            hi.sugar, hi.spice, lo.sugar, lo.spice = old
            return nothing
        end
        push!(m.trade_log, Exchange(price, sugar, spice, hi, lo))
    end
end

"""After moving, an agent trades through T exactly once with each neighbour, in random order (p.107)."""
function trade_with_neighbors!(m::Model, a::Agent)
    for b in shuffle!(m.rng, neighbors_of(m, a))
        bargain!(m, a, b)
    end
    return nothing
end
