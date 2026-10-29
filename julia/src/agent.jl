# The single agent type (App. A, p.180: one class carries every rule's state), ported from sugarscape/agent.py,
# with the records the rules produce: exchanges (rule T) and loans (rule L).

"""
    Agent

Field for field the Python `Agent`. Coordinates are 0-based as in Python. Representations that differ (design,
"Free to differ"): `sex` is `:none`, `:F` or `:M`; cultural tags are the low `ntags` bits of `tags` (bit i-1 is tag
i; `ntags == 0` means no tags); immune strings are the low `nimmune` bits of `immune` and `immune_genotype`;
`diseases` holds interned disease ids in order of infection; `slot` is the agent's index in `Model.agents`. The
last five fields are xxl's (`speed`, `memory`, `moved_dist`, `target_remembered`, `travel_free`) and stay at their
defaults without it.
"""
mutable struct Agent
    id::Int
    x::Int
    y::Int
    vision::Int
    metabolism::Int
    sugar::Float64
    initial_sugar::Float64
    max_age::Float64
    age::Int
    alive::Bool
    moved::Bool
    neighbors::Vector{Agent}
    # Chapter III
    sex::Symbol
    fertility_start::Float64
    fertility_end::Float64
    children::Vector{Agent}
    tags::UInt64
    ntags::Int
    friends::Vector{Tuple{Agent,Int}}
    # Chapter IV
    spice::Float64
    initial_spice::Float64
    spice_metabolism::Int
    foresight::Int
    last_income::Float64
    # Chapter V
    immune_genotype::UInt64
    immune::UInt64
    nimmune::Int
    diseases::Vector{Int}
    disease_fee::Float64
    disp_x::Int
    disp_y::Int
    slot::Int
    # xxl (Julia only): the speed trait (0 = none), the sites remembered, and this move's bookkeeping
    speed::Int
    memory::Vector{Remembered}
    moved_dist::Float64
    target_remembered::Bool
    travel_free::Bool
end

function Agent(id, x, y, vision, metabolism, sugar, max_age=Inf)
    return Agent(
        id,
        x,
        y,
        vision,
        metabolism,
        Float64(sugar),
        Float64(sugar),
        Float64(max_age),
        0,
        true,
        false,
        Agent[],
        :none,
        Inf,
        -Inf,
        Agent[],
        UInt64(0),
        0,
        Tuple{Agent,Int}[],
        0.0,
        0.0,
        0,
        0,
        0.0,
        UInt64(0),
        UInt64(0),
        0,
        Int[],
        0.0,
        0,
        0,
        0,
        0,
        Remembered[],
        0.0,
        false,
        false,
    )
end

function Base.show(io::IO, a::Agent)
    return print(io, "Agent(", a.id, " at (", a.x, ", ", a.y, "), sugar ", a.sugar, ")")
end

"""Sugar metabolism including the fee for each active disease (p.143)."""
sugar_burn(a::Agent) = a.metabolism + a.disease_fee * length(a.diseases)

"""One exchange of rule T: `sugar` moves to `a` (the higher MRS), `spice` to `b`, at `price` spice per sugar."""
struct Exchange
    price::Float64
    sugar::Float64
    spice::Float64
    a::Agent
    b::Agent
end

"""A sugar loan of rule L: `due` is owed at `due_t`."""
mutable struct Loan
    lender::Agent
    borrower::Agent
    principal::Float64
    due::Float64
    due_t::Int
end
