# xxl: saving a model part-way through a seed and reading it back. `serialize` follows an object's references recursively,
# and agents reach each other through their neighbours, children and friends: at 54,000 agents that nests 40,000 agents
# deep, on a stack that holds 22,000. So agents go in a flat table, their links as ids, and `serialize` sees only the table.

const AGENT_LINK_FIELDS = (:neighbors, :children, :friends)
const AGENT_PLAIN_FIELDS = Tuple(f for f in fieldnames(Agent) if !(f in AGENT_LINK_FIELDS))
# The model's fields that hold agents or records of them; every other field is saved as it is.
const MODEL_LINK_FIELDS = (:grid, :agents, :dead_this_step, :trade_log, :loans, :debts, :infection_log, :order, :sight)

"""
    FlatModel

A [`Model`](@ref) with no references between agents. `table` is one column per plain agent field, over every agent the
model can reach, the dead that the living still hold included; `plain` is the model's own fields that hold no agents;
the rest are the links, by agent id (loans in `debts` by their place in `loans`, as both hold the same objects).
"""
struct FlatModel
    plain::Dict{Symbol,Any}
    table::Dict{Symbol,Any}
    neighbors::Vector{Vector{Int}}
    children::Vector{Vector{Int}}
    friends::Vector{Vector{Tuple{Int,Int}}}
    grid::Matrix{Int}  # -1 for an empty site
    agents::Vector{Int}
    dead_this_step::Vector{Int}
    order::Vector{Int}
    sight::Vector{Int}
    trade_log::Vector{Tuple{Float64,Float64,Float64,Int,Int}}
    loans::Vector{Tuple{Int,Int,Float64,Float64,Int}}
    debts::Dict{Int,Vector{Int}}
    infection_log::Vector{Tuple{Int,Int}}
end

"""Every agent `m` can reach, by id, found without recursion. Two agents with one id can't be told apart: an error."""
function reachable_agents(m::Model)
    stack = [m.agents; m.dead_this_step; m.order; m.sight]
    for a in m.grid
        a === nothing || push!(stack, a)
    end
    for e in m.trade_log
        push!(stack, e.a, e.b)
    end
    for loan in m.loans
        push!(stack, loan.lender, loan.borrower)
    end
    for (source, target) in m.infection_log
        push!(stack, source, target)
    end
    seen = Dict{Int,Agent}()
    while !isempty(stack)
        a = pop!(stack)
        known = get(seen, a.id, nothing)
        if known !== nothing
            known === a || error("two agents have the id $(a.id)")
            continue
        end
        seen[a.id] = a
        append!(stack, a.neighbors)
        append!(stack, a.children)
        for (b, _) in a.friends
            push!(stack, b)
        end
    end
    return sort!(collect(values(seen)); by=a -> a.id)
end

"""The flat form of `m`, with nothing of `m` changed."""
function flat_model(m::Model)
    agents = reachable_agents(m)
    ids(list) = Int[a.id for a in list]
    place = IdDict{Loan,Int}(loan => i for (i, loan) in enumerate(m.loans))
    return FlatModel(
        Dict{Symbol,Any}(f => getfield(m, f) for f in fieldnames(typeof(m)) if !(f in MODEL_LINK_FIELDS)),
        Dict{Symbol,Any}(f => [getfield(a, f) for a in agents] for f in AGENT_PLAIN_FIELDS),
        [ids(a.neighbors) for a in agents],
        [ids(a.children) for a in agents],
        [Tuple{Int,Int}[(b.id, n) for (b, n) in a.friends] for a in agents],
        Int[a === nothing ? -1 : a.id for a in m.grid],
        ids(m.agents),
        ids(m.dead_this_step),
        ids(m.order),
        ids(m.sight),
        [(e.price, e.sugar, e.spice, e.a.id, e.b.id) for e in m.trade_log],
        [(l.lender.id, l.borrower.id, l.principal, l.due, l.due_t) for l in m.loans],
        Dict{Int,Vector{Int}}(id => Int[place[l] for l in loans] for (id, loans) in m.debts),
        Tuple{Int,Int}[(source.id, target.id) for (source, target) in m.infection_log],
    )
end

"""The model of a [`FlatModel`](@ref): one object per agent and per loan, however many lists hold it."""
function model_from_flat(f::FlatModel)
    agents = [Agent(0, 0, 0, 0, 0, 0.0) for _ in f.table[:id]]
    for name in AGENT_PLAIN_FIELDS, (a, v) in zip(agents, f.table[name])
        setfield!(a, name, v)
    end
    by_id = Dict{Int,Agent}(a.id => a for a in agents)
    linked(ids) = Agent[by_id[id] for id in ids]
    for (i, a) in enumerate(agents)
        a.neighbors = linked(f.neighbors[i])
        a.children = linked(f.children[i])
        a.friends = Tuple{Agent,Int}[(by_id[id], n) for (id, n) in f.friends[i]]
    end
    loans = Loan[Loan(by_id[l[1]], by_id[l[2]], l[3], l[4], l[5]) for l in f.loans]
    grid = Matrix{Union{Nothing,Agent}}(undef, size(f.grid))
    for i in eachindex(grid)
        grid[i] = f.grid[i] < 0 ? nothing : by_id[f.grid[i]]
    end
    links = Dict{Symbol,Any}(
        :grid => grid,
        :agents => linked(f.agents),
        :dead_this_step => linked(f.dead_this_step),
        :order => linked(f.order),
        :sight => linked(f.sight),
        :trade_log => Exchange[Exchange(e[1], e[2], e[3], by_id[e[4]], by_id[e[5]]) for e in f.trade_log],
        :loans => loans,
        :debts => Dict{Int,Vector{Loan}}(id => Loan[loans[i] for i in places] for (id, places) in f.debts),
        :infection_log => Tuple{Agent,Agent}[(by_id[s], by_id[t]) for (s, t) in f.infection_log],
    )
    return Model((name in MODEL_LINK_FIELDS ? links[name] : f.plain[name] for name in fieldnames(Model))...)
end

const DIGEST_BYTES = 32  # sha256

"""
`f()`, tried again for some seconds if the file system refuses it: on Windows a file can't be replaced or removed while
anything has it open, as a virus scanner or an indexer may for a moment.
"""
retrying(f) = retry(f; delays=[0.1, 0.5, 1.0, 2.0, 5.0], check=(_, e) -> e isa Base.IOError)()

"""
    save_checkpoint(path, header, state; t=-1)

Writes `state`, a named tuple (a `Model` in it goes flat), under `header`, text saying what it belongs to, and the period
`t` it was saved at, to `path`, replacing what was there in one step. The bytes go to `<path>.tmp`, then a checksum of
them goes in at the start, and only then is the file renamed: `path` always holds a whole save. (Not `mv` with `force`:
when a rename fails it deletes the old file and may fall back on a copy, and the old file is all there would be.)

The file: the sha256 of all that follows, `t` and the header's length as Int64, the header, then the serialized state.
"""
function save_checkpoint(path::AbstractString, header::AbstractString, state::NamedTuple; t::Int=-1)
    tmp = path * ".tmp"
    open(tmp, "w+") do io
        write(io, zeros(UInt8, DIGEST_BYTES))
        write(io, Int64(t), Int64(sizeof(header)), header)
        serialize(io, map(v -> v isa Model ? flat_model(v) : v, state))
        flush(io)
        seek(io, DIGEST_BYTES)
        digest = sha256(io)
        seek(io, 0)
        write(io, digest)
    end
    retrying(() -> Base.rename(tmp, path))
    return nothing
end

"""
What a checkpoint (a path, or a stream at its start) says of itself, `(; header, t)`, or `nothing` if it is not whole: too
short, or not matching its checksum. Leaves the stream at the start of the state.
"""
function checkpoint_label(io::IO)
    stored = read(io, DIGEST_BYTES)
    length(stored) == DIGEST_BYTES && sha256(io) == stored || return nothing
    seek(io, DIGEST_BYTES)
    t, n = read(io, Int64), read(io, Int64)
    return (; header=String(read(io, n)), t=Int(t))
end
checkpoint_label(path::AbstractString) = open(checkpoint_label, path)

"""
    load_checkpoint(path, header) -> state or nothing

The state saved at `path`, its model rebuilt; `nothing` if there is no file or it is damaged, which only its checksum may
decide, as `deserialize` does not validate what it reads. `ArgumentError` if it is whole but belongs to something else.
"""
function load_checkpoint(path::AbstractString, header::AbstractString)
    isfile(path) || return nothing
    return open(path) do io
        label = checkpoint_label(io)
        label === nothing && return nothing
        label.header == header || throw(ArgumentError("$path belongs to another run; delete it to start that seed again"))
        return map(v -> v isa FlatModel ? model_from_flat(v) : v, deserialize(io))
    end
end
