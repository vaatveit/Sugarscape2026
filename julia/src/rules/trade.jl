# Agent trade rule T: bilateral exchange of sugar and spice (pp.101-107, App. B p.184; sugarscape/rules/trade.py).

valid_mrs(v::Float64) = isfinite(v) && v > 0

"""
    bargain!(m, a, b)

Rule T between two neighbours (p.105). While their MRSs differ: the price is the geometric mean of the MRSs (eq. 4);
the agent with the higher MRS buys sugar with spice (p > 1: p spice for 1 sugar; p < 1: 1 spice for 1/p sugar). The
exchange happens only if both agents' welfare strictly rises and their MRSs don't cross (fn 17); otherwise
bargaining ends. An MRS of 0, infinity, or undefined means no trade (our call). trade_rounding="down" rounds the
amount of p or 1/p down to a whole unit (VAR-inttrade); the price stays p. Each exchange goes to `m.trade_log`.

xxl rule 15, the trade step (`trade_step` below 1): each exchange moves that share of the book's unit, both amounts
multiplied by it, at the same price; the meeting goes on, step after step, until one fails the tests. At 1 it is the
book's unit, untouched.

xxl rule 14, the meeting's price (`trade_price = "meeting"`): the MRSs, the price and which agent buys sugar are
set once, when the meeting starts; every unit then trades at that price, under the same unit sizes and tests, until
one fails. Off, the price is set afresh before every unit, as above.

xxl rule 13 reads the prices back: each exchange leaves its price as both agents' `last_price`, and, when the model
keeps a local price (`m.site_price` isn't empty), its log and period at both agents' sites, the latest exchange at a
site standing. None of this draws or touches the exchange itself.
"""
function bargain!(m::Model, a::Agent, b::Agent)
    cultural = m.config.cultural_preferences
    whole = m.config.trade_rounding == "down"
    step = xxl_on(m.config, :trade_step) ? m.config.xxl.trade_step : 1.0
    if xxl_on(m.config, :trade_price)  # xxl rule 14: one price for the whole meeting
        ma, mb = mrs(a, cultural), mrs(b, cultural)
        (!(valid_mrs(ma) && valid_mrs(mb)) || ma == mb) && return nothing
        hi, lo = ma > mb ? (a, b) : (b, a)
        price = sqrt(ma * mb)
        while trade_unit!(m, hi, lo, price, cultural, whole, step)
        end
        return nothing
    end
    while true
        ma, mb = mrs(a, cultural), mrs(b, cultural)
        (!(valid_mrs(ma) && valid_mrs(mb)) || ma == mb) && return nothing
        hi, lo = ma > mb ? (a, b) : (b, a)
        price = sqrt(ma * mb)
        trade_unit!(m, hi, lo, price, cultural, whole, step) || return nothing
    end
end

"""
    trade_unit!(m, hi, lo, price, cultural, whole, step)

One unit of rule T at `price`, `hi` buying sugar from `lo` (see `bargain!`), `step` of the book's unit (rule 15; 1 is
the book's): made and logged if it passes the tests, undone otherwise. Returns whether it was made.
"""
function trade_unit!(
    m::Model, hi::Agent, lo::Agent, price::Float64, cultural::Bool, whole::Bool, step::Float64
)
    sugar, spice =
        price > 1 ? (1.0, price) : (price < 1 ? (1.0 / price, 1.0) : (1.0, 1.0))
    if whole
        sugar, spice = floor(sugar), floor(spice)
    end
    if step != 1.0
        sugar, spice = sugar * step, spice * step
    end
    old = (hi.sugar, hi.spice, lo.sugar, lo.spice)
    hi.sugar, hi.spice = hi.sugar + sugar, hi.spice - spice
    lo.sugar, lo.spice = lo.sugar - sugar, lo.spice + spice
    accepted =  # the cheapest tests first: nothing here changes anything, so the order can't matter
        min(hi.sugar, hi.spice, lo.sugar, lo.spice) > 0 &&
        mrs(hi, cultural) >= mrs(lo, cultural) &&  # no crossing over
        welfare_rises(hi, hi.sugar, hi.spice, old[1], old[2], cultural) &&
        welfare_rises(lo, lo.sugar, lo.spice, old[3], old[4], cultural)
    if !accepted
        hi.sugar, hi.spice, lo.sugar, lo.spice = old
        return false
    end
    push!(m.trade_log, Exchange(price, sugar, spice, hi, lo))
    hi.last_price = lo.last_price = price
    if !isempty(m.site_price)
        lp = log(price)
        m.site_price[hi.x + 1, hi.y + 1], m.site_price_t[hi.x + 1, hi.y + 1] = lp, m.t
        m.site_price[lo.x + 1, lo.y + 1], m.site_price_t[lo.x + 1, lo.y + 1] = lp, m.t
    end
    return true
end

"""After moving, an agent trades through T exactly once with each neighbour, in random order (p.107)."""
function trade_with_neighbors!(m::Model, a::Agent)
    for b in shuffle!(m.rng, neighbors_of(m, a))
        bargain!(m, a, b)
    end
    return nothing
end
