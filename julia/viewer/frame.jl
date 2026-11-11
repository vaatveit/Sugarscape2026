# One period's map frame: every agent with its codes, the kills and tribe changes of the period, the Lorenz curve and the
# landscape's levels, and its binary layout. Capturing reads the model and never changes it.

using Sugarscape: gini

const FRAME_MAGIC = b"SXV1"
const FRAME_HEADER_BYTES = 32
const LORENZ_POINTS = 101

"""One period's frame (see [`encode_frame`](@ref) for the layout). Agent vectors are all `n_agents` long, cell vectors `width * height`."""
struct ViewerFrame
    t::Int
    width::Int
    height::Int
    ntags::Int
    sugar::Vector{Float64}
    spice::Vector{Float64}
    lorenz::Vector{Float64}
    gini::Float64
    id::Vector{UInt32}
    x::Vector{UInt16}
    y::Vector{UInt16}
    tags::Vector{UInt16}
    age::Vector{UInt16}
    lender::Vector{UInt16}  # active loans as lender
    borrower::Vector{UInt16}  # active loans as borrower
    kill_x::Vector{UInt16}
    kill_y::Vector{UInt16}
    change_x::Vector{UInt16}
    change_y::Vector{UInt16}
    tribe::Vector{UInt8}
    culture::Vector{UInt8}
    band::Vector{UInt8}
    disease_step::Vector{UInt8}
    role::Vector{UInt8}
    diseases::Vector{UInt8}
    cell_sugar::Vector{UInt8}  # index y * width + x, in eighths
    cell_spice::Vector{UInt8}
end

n_agents(f::ViewerFrame) = length(f.id)
n_kills(f::ViewerFrame) = length(f.kill_x)
n_changes(f::ViewerFrame) = length(f.change_x)

"""`lorenz_curve(wealths)`: 101 points, point i the wealth share of the poorest `round(Int, i * n / 100)` agents (NaN when there are none or no wealth)."""
function lorenz_curve(wealths::AbstractVector{<:Real})
    n = length(wealths)
    x = sort(Float64.(wealths))
    total = sum(x; init=0.0)
    (n == 0 || total == 0) && return fill(NaN, LORENZ_POINTS)
    cum = cumsum(x)
    return [(k = round(Int, i * n / 100); k == 0 ? 0.0 : cum[k] / total) for i in 0:100]
end

function cell_levels(levels::Matrix{Float64}, width::Int, height::Int)
    out = Vector{UInt8}(undef, width * height)
    for y in 0:(height - 1), x in 0:(width - 1)
        out[y * width + x + 1] = cell_eighths(levels[x + 1, y + 1])
    end
    return out
end

"""
    capture_frame(m, prev, seen) -> ViewerFrame

The frame of the model's current period. `prev` and `seen` are the combat readings' previous tribes and whether they exist:
call this after `step!` and before `combat_period!` overwrites them. Reads the model only.
"""
function capture_frame(m::Model, prev::Dict{Int,Symbol}, seen::Bool)
    m.config.tag_length <= 16 || error("a frame carries tags in 16 bits, not $(m.config.tag_length)")
    agents = m.agents
    lend = Dict{Int,Int}()
    borrow = Dict{Int,Int}()
    for l in m.loans
        lend[l.lender.id] = get(lend, l.lender.id, 0) + 1
        borrow[l.borrower.id] = get(borrow, l.borrower.id, 0) + 1
    end
    roles = credit_roles(m)
    kill_x, kill_y = UInt16[], UInt16[]
    for a in m.dead_this_step
        a.id in m.killed || continue
        push!(kill_x, a.x)
        push!(kill_y, a.y)
    end
    change_x, change_y = UInt16[], UInt16[]
    for a in agents
        if seen && haskey(prev, a.id) && prev[a.id] != tribe(a)
            push!(change_x, a.x)
            push!(change_y, a.y)
        end
    end
    wealth = [a.sugar + a.spice for a in agents]
    w, h = m.config.width, m.config.height
    return ViewerFrame(
        m.t, w, h, m.config.tag_length,
        [a.sugar for a in agents], [a.spice for a in agents],
        lorenz_curve(wealth), gini(wealth),
        [UInt32(a.id) for a in agents],
        [UInt16(a.x) for a in agents], [UInt16(a.y) for a in agents],
        [UInt16(a.tags) for a in agents], [UInt16(a.age) for a in agents],
        [UInt16(get(lend, a.id, 0)) for a in agents], [UInt16(get(borrow, a.id, 0)) for a in agents],
        kill_x, kill_y, change_x, change_y,
        [tribe_code(a) for a in agents], [culture_ones(a) for a in agents], [wealth_band(v) for v in wealth],
        [disease_step(length(a.diseases)) for a in agents], [get(roles, a.id, ROLE_NONE) for a in agents],
        [UInt8(length(a.diseases)) for a in agents],
        cell_levels(m.landscape.sugar, w, h), cell_levels(m.landscape.spice, w, h),
    )
end

"""
    encode_frame(f) -> Vector{UInt8}

Little-endian: a 32-byte header (`SXV1`, t Int32, width and height UInt16, n_agents, n_kills, n_changes UInt32, ntags
UInt8, 7 zero bytes), then Float64 (sugar, spice, lorenz, gini), UInt32 (id), UInt16 (x, y, tags, age, lender, borrower,
kill x, kill y, change x, change y), UInt8 (tribe, culture, band, disease step, role, diseases, cell sugar, cell spice).
Each section starts at a multiple of its element size.
"""
function encode_frame(f::ViewerFrame)::Vector{UInt8}
    io = IOBuffer()
    write(io, FRAME_MAGIC)
    write(io, htol(Int32(f.t)), htol(UInt16(f.width)), htol(UInt16(f.height)))
    write(io, htol(UInt32(n_agents(f))), htol(UInt32(n_kills(f))), htol(UInt32(n_changes(f))))
    write(io, UInt8(f.ntags))
    write(io, zeros(UInt8, 7))
    @assert position(io) == FRAME_HEADER_BYTES
    for v in (f.sugar, f.spice, f.lorenz)
        write(io, htol.(v))
    end
    write(io, htol(f.gini))
    write(io, htol.(f.id))
    for v in (f.x, f.y, f.tags, f.age, f.lender, f.borrower, f.kill_x, f.kill_y, f.change_x, f.change_y)
        write(io, htol.(v))
    end
    for v in (f.tribe, f.culture, f.band, f.disease_step, f.role, f.diseases, f.cell_sugar, f.cell_spice)
        write(io, v)
    end
    return take!(io)
end
