// Disease processes E in the turn and the disease fee, line for line with Python's sugarscape.rules.disease and
// Agent.sugar_burn (Chapter V, pp.143-147; plan 2026-10-27-gpu-parity-part-d, Task 3). Included only by model.cu (via
// turn.cuh).
#ifndef SRC_DISEASE_CUH_
#define SRC_DISEASE_CUH_

#include "disease.h"
#include "looks.cuh"
#include "rules.cuh"
#include "store.h"

// Python's Agent.sugar_burn: metabolism plus the fee for each disease carried (p.143); the metabolism exactly without.
__device__ __forceinline__ double sugar_burn(const Store& s, unsigned int row, double fee) {
    return static_cast<double>(s.metabolism[row]) + fee * static_cast<double>(s.n_diseases[row]);
}

template <typename API>
__device__ __forceinline__ bool immune_to(API* FLAMEGPU, uint64_t immune, int immune_length, unsigned int id) {
    const auto& env = FLAMEGPU->environment;
    return is_immune(immune, immune_length, env.template getProperty<uint64_t, MAX_DISEASES>("disease_bits", id),
                     static_cast<int>(env.template getProperty<unsigned int, MAX_DISEASES>("disease_len", id)));
}

// Python's infect (p.145): the row contracts the disease (a canonical id) unless it carries it or is immune to it.
template <typename API>
__device__ bool infect(API* FLAMEGPU, const Store& s, int r, unsigned int id, int immune_length) {
    const unsigned int n = s.n_diseases[r];
    for (unsigned int k = 0; k < n; ++k) {
        if (s.diseases[r * MAX_DISEASES + k] == id) return false;
    }
    if (immune_to(FLAMEGPU, s.immune[r], immune_length, id)) return false;
    s.diseases[r * MAX_DISEASES + n] = static_cast<uint8_t>(id);  // distinct canonical ids: n < MAX_DISEASES
    s.n_diseases[r] = n + 1u;
    return true;
}

// Python's transmit (p.145): for each agent on the four sites around it now (newborns too; touch point 14), in a random
// order, a disease the agent carries is drawn at random and given to that neighbour; each infection is counted.
template <typename API>
__device__ void disease_transmit(API* FLAMEGPU, const Store& s, unsigned int row, int immune_length) {
    const unsigned int carried = s.n_diseases[row];
    if (carried == 0u) return;
    const auto& env = FLAMEGPU->environment;
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    const int a = static_cast<int>(row);
    int neighbours[4];
    int n = 0;
    for (int d = 0; d < 4; ++d) {
        const unsigned int site = static_cast<unsigned int>(wrap(s.x[a] + dir_dx(d), w) + wrap(s.y[a] + dir_dy(d), h) * w);
        touch(s, site, s.rank[a], 14);
        if (s.site_row[site] >= 0) neighbours[n++] = s.site_row[site];
    }
    for (int i = n - 1; i > 0; --i) {  // rng.permutation
        const int j = draw_between(FLAMEGPU, 0, i);
        const int t = neighbours[i];
        neighbours[i] = neighbours[j];
        neighbours[j] = t;
    }
    for (int i = 0; i < n; ++i) {
        const unsigned int id = s.diseases[row * MAX_DISEASES + draw_between(FLAMEGPU, 0, static_cast<int>(carried) - 1)];
        if (infect(FLAMEGPU, s, neighbours[i], id, immune_length)) atomicAdd(s.infections, 1u);
    }
}

// Python's immune_response (p.144): one learning step for each disease carried, in order of infection; a disease the
// immune system now matches leaves the list, which keeps its order.
template <typename API>
__device__ void immune_response(API* FLAMEGPU, const Store& s, unsigned int row, int immune_length) {
    const auto& env = FLAMEGPU->environment;
    uint64_t immune = s.immune[row];
    unsigned int kept = 0;
    const unsigned int n = s.n_diseases[row];
    for (unsigned int k = 0; k < n; ++k) {
        const unsigned int id = s.diseases[row * MAX_DISEASES + k];
        const bool matched = immune_step(immune, immune_length, env.template getProperty<uint64_t, MAX_DISEASES>("disease_bits", id),
                                         static_cast<int>(env.template getProperty<unsigned int, MAX_DISEASES>("disease_len", id)));
        if (!matched) s.diseases[row * MAX_DISEASES + kept++] = static_cast<uint8_t>(id);
    }
    s.immune[row] = immune;
    s.n_diseases[row] = kept;
}

#endif  // SRC_DISEASE_CUH_
