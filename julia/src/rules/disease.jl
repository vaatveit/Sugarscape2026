# Immune systems and disease processes E (Chapter V, pp.141-147, App. B p.185; sugarscape/rules/disease.py).
# Immune systems are the low `nimmune` bits of a UInt64; a disease is interned by its (bits, length), so equal strings
# share one id as Python's equal tuples are one disease.

"""The id of the disease with these bits and length, interning it on first sight."""
function intern_disease!(m::Model, bits::UInt64, len::Int)
    return get!(m.disease_ids, (bits, len)) do
        push!(m.disease_bits, bits)
        push!(m.disease_len, len)
        return length(m.disease_bits)
    end
end

"""
    nearest_substring(immune, nimmune, bits, len) -> (start, distance)

(0-based start, Hamming distance) of the window of the immune system closest to the disease; ties go to the
leftmost window (p.142 fn 11).
"""
function nearest_substring(immune::UInt64, nimmune::Int, bits::UInt64, len::Int)
    mask = tag_mask(len)
    best_start, best_d = 0, len + 1
    for start in 0:(nimmune - len)
        d = count_ones(((immune >> start) ⊻ bits) & mask)
        if d < best_d
            best_start, best_d = start, d
            d == 0 && break
        end
    end
    return best_start, best_d
end

"""Immune iff the disease is a substring of the immune system (p.142)."""
function is_immune(immune::UInt64, nimmune::Int, bits::UInt64, len::Int)
    return nearest_substring(immune, nimmune, bits, len)[2] == 0
end

"""
    immune_step!(a, bits, len) -> matched

One period of learning (p.144): flip the first bit at which the nearest window differs from the disease. Returns
whether the disease now matches.
"""
function immune_step!(a::Agent, bits::UInt64, len::Int)
    start, distance = nearest_substring(a.immune, a.nimmune, bits, len)
    distance == 0 && return true
    diff = ((a.immune >> start) ⊻ bits) & tag_mask(len)
    a.immune ⊻= UInt64(1) << (start + trailing_zeros(diff))
    return distance == 1
end

"""Contract a disease unless immune to it or already carrying it (p.145)."""
function infect!(m::Model, a::Agent, id::Int)
    (
        id in a.diseases ||
        is_immune(a.immune, a.nimmune, m.disease_bits[id], m.disease_len[id])
    ) && return false
    push!(a.diseases, id)
    return true
end

"""
Agent immune response rule (p.144), once per period for each carried disease, in order of infection; a disease is
cleared the moment the immune system matches it, so a one-bit gap costs one period of illness (p.143).
"""
function immune_response!(m::Model, a::Agent)
    filter!(id -> !immune_step!(a, m.disease_bits[id], m.disease_len[id]), a.diseases)
    return nothing
end

"""
Agent disease transmission rule (p.145): for each neighbour, in random order, a disease that currently afflicts the
agent is selected at random and given to it. New infections go to `m.infection_log` (p.150).
"""
function disease_transmit!(m::Model, a::Agent)
    isempty(a.diseases) && return nothing
    for other in shuffle!(m.rng, neighbors_of(m, a))
        id = a.diseases[rand(m.rng, 1:length(a.diseases))]
        other.nimmune > 0 && infect!(m, other, id) && push!(m.infection_log, (a, other))
    end
    return nothing
end

"""p.147: a master list of random diseases, each of random length."""
function init_disease_list!(m::Model)
    for _ in 1:(m.config.disease_list)
        len = draw(m.rng, m.config.disease_length)
        push!(m.disease_list, intern_disease!(m, rand(m.rng, UInt64) & tag_mask(len), len))
    end
    return nothing
end

"""p.147: initial agents get distinct diseases from the list (in creation order, as Python's agent list)."""
function infect_founders!(m::Model)
    for a in sort(m.agents; by=a -> a.id)
        for i in sample_distinct(m.rng, length(m.disease_list), m.config.diseases_per_agent)
            infect!(m, a, m.disease_list[i])
        end
    end
    return nothing
end
