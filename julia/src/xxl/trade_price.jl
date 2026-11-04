# xxl rule 13: the price an agent expects to trade at, for the move that counts on trade
# (docs/superpowers/specs/2026-11-03-xxl-trade-design.md, "Part 2"). `bargain!` records the prices; this reads them.

"""How many periods back a site's price still counts for the local price: the last 10, this one included (our call)."""
const LOCAL_PRICE_PERIODS = 10

"""
    expected_price(m, a, looked) -> Float64

The price, in spice per sugar (the unit of `Exchange.price`), that agent `a` expects to trade at after a move. `looked`
is the sites it looked at (`look!`'s list, 0-based). With `trade_move = "own"`: its last price if it has made an exchange,
else its MRS. With `"local"`: the geometric mean of the latest prices at its own site and the looked-at sites that had
an exchange in the last [`LOCAL_PRICE_PERIODS`](@ref) periods (a site counts once), else its MRS. `NaN` if there is no
price and the MRS isn't one (`valid_mrs`).
"""
function expected_price(m::Model, a::Agent, looked::Vector{Tuple{Int,Int}})
    own_mrs() = (v = mrs(a, m.config.cultural_preferences); valid_mrs(v) ? v : NaN)
    if m.config.xxl.trade_move == "own"
        return isfinite(a.last_price) ? a.last_price : own_mrs()
    end
    since = max(m.t - LOCAL_PRICE_PERIODS + 1, 0)  # never back to site_price_t's -1, no exchange yet
    total, n = 0.0, 0
    site_x, site_y = a.x + 1, a.y + 1
    if @inbounds m.site_price_t[site_x, site_y] >= since
        total += @inbounds m.site_price[site_x, site_y]
        n += 1
    end
    for (x, y) in looked
        (x == a.x && y == a.y) && continue  # the agent's own site is counted above
        if @inbounds m.site_price_t[x + 1, y + 1] >= since
            total += @inbounds m.site_price[x + 1, y + 1]
            n += 1
        end
    end
    return n == 0 ? own_mrs() : exp(total / n)
end
