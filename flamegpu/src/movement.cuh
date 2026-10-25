// Movement rule M in parallel: rounds of atomic claims inside a sub-model (design: One period, step 2).
// Included only by model.cu.
#ifndef SRC_MOVEMENT_CUH_
#define SRC_MOVEMENT_CUH_

#include "host_state.h"
#include "model.h"

// Directions in the Python project's VON_NEUMANN order: east, west, north, south.
__device__ __constant__ int MOVE_DX[4] = {1, -1, 0, 0};
__device__ __constant__ int MOVE_DY[4] = {0, 0, 1, -1};

constexpr unsigned int MAX_ROUNDS = 4095;  // 12 bits of the claim key

// round (12 bits) | priority (20 bits) | agent id (32 bits): the largest key at a site wins it.
__device__ __forceinline__ uint64_t claim_key(unsigned int round, unsigned int priority, flamegpu::id_t id) {
    return (static_cast<uint64_t>(round & 0xFFFu) << 52) | (static_cast<uint64_t>(priority & 0xFFFFFu) << 32) |
           static_cast<uint64_t>(id);
}

__device__ __forceinline__ int wrap(int v, int n) { return ((v % n) + n) % n; }

// A 32-bit integer hash (lowbias32: Wellons, "Prospecting for Hash Functions").
__device__ __forceinline__ unsigned int mix32(unsigned int h) {
    h ^= h >> 16;
    h *= 0x7FEB352Du;
    h ^= h >> 15;
    h *= 0x846CA68Bu;
    h ^= h >> 16;
    return h;
}

// With look stride s > 1, the distance looked at in direction d (VON_NEUMANN index) and stretch k: s·k plus an offset
// uniform on 1..s (Python look_distances). A pure function of the period's look seed, so every movement round of a
// period sees the same sites (xl design, section 2a).
__device__ __forceinline__ int look_distance(unsigned int look_seed, int d, int k, int stride) {
    const unsigned int h = mix32(mix32(look_seed ^ (static_cast<unsigned int>(d) * 0x9E3779B9u)) ^
                                 (static_cast<unsigned int>(k + 1) * 0x85EBCA6Bu));
    return stride * k + 1 + static_cast<int>(h % static_cast<unsigned int>(stride));
}

// Scan (reads occupied, sugar, pollution; writes claim): the nearest best unoccupied site in view, scanned as
// candidate_sites does — own site at distance 0, then the four directions in a random order out to vision: every
// site, or with a look stride one site per stretch.
FLAMEGPU_AGENT_FUNCTION(scan, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<unsigned int>("settled")) return flamegpu::ALIVE;
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
    const int x = FLAMEGPU->getVariable<int>("x");
    const int y = FLAMEGPU->getVariable<int>("y");
    const int vision = FLAMEGPU->getVariable<int>("vision");
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");

    const unsigned int own = static_cast<unsigned int>(x + y * w);
    unsigned int best = own;
    int best_dist = 0;
    float best_score = static_cast<float>(sugar[own]) / (1.0f + static_cast<float>(pollution[own]));

    int order[4] = {0, 1, 2, 3};
    for (int i = 3; i > 0; --i) {  // Fisher-Yates; uniform(0, i) can return i + 1 at the float endpoint
        const int j = min(FLAMEGPU->random.uniform<int>(0, i), i);
        const int tmp = order[i];
        order[i] = order[j];
        order[j] = tmp;
    }
    const int stride = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("look_stride"));
    const unsigned int look_seed = stride > 1 ? FLAMEGPU->getVariable<unsigned int>("look_seed") : 0u;
    for (int k = 0; k < 4; ++k) {
        const int d = order[k];
        const int looks = vision / stride;  // validate(): vision is in whole strides
        for (int i = 0; i < looks; ++i) {
            const int dist = stride == 1 ? i + 1 : look_distance(look_seed, d, i, stride);
            const unsigned int site =
                static_cast<unsigned int>(wrap(x + MOVE_DX[d] * dist, w) + wrap(y + MOVE_DY[d] * dist, h) * w);
            if (static_cast<unsigned int>(occupied[site])) continue;  // check occupancy before reading the site
            const float score = static_cast<float>(sugar[site]) / (1.0f + static_cast<float>(pollution[site]));
            if (score > best_score || (score == best_score && dist < best_dist)) {
                best = site;
                best_dist = dist;
                best_score = score;
            }
        }
    }
    FLAMEGPU->setVariable<unsigned int>("target", best);
    if (best != own) {
        auto claim = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("claim");
        const unsigned int round = FLAMEGPU->environment.getProperty<unsigned int>("round");
        claim[best].max(claim_key(round, FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID()));
    }
    return flamegpu::ALIVE;
}

// Resolve (reads claim; writes occupied, sugar, pollution): winners move, harvest all the site's sugar, and settle.
FLAMEGPU_AGENT_FUNCTION(resolve, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<unsigned int>("settled")) return flamegpu::ALIVE;
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    const int x = FLAMEGPU->getVariable<int>("x");
    const int y = FLAMEGPU->getVariable<int>("y");
    const unsigned int own = static_cast<unsigned int>(x) + static_cast<unsigned int>(y) * w;
    const unsigned int target = FLAMEGPU->getVariable<unsigned int>("target");
    if (target != own) {
        auto claim = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("claim");
        const unsigned int round = FLAMEGPU->environment.getProperty<unsigned int>("round");
        const uint64_t key = claim_key(round, FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID());
        if (static_cast<uint64_t>(claim[target]) != key) return flamegpu::ALIVE;  // lost: scan again next round
    }
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    if (target != own) {
        occupied[own].exchange(0u);
        occupied[target].exchange(1u);
        FLAMEGPU->setVariable<int>("x", static_cast<int>(target % w));
        FLAMEGPU->setVariable<int>("y", static_cast<int>(target / w));
        FLAMEGPU->setVariable<unsigned int>("moved", 1u);
    }
    const float harvest = sugar[target].exchange(0.0f);
    FLAMEGPU->setVariable<float>("sugar", FLAMEGPU->getVariable<float>("sugar") + harvest);
    if (FLAMEGPU->environment.getProperty<unsigned int>("pollution_active")) {
        auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
        pollution[target] += FLAMEGPU->environment.getProperty<float>("pollution_alpha") * harvest;  // production (p.47)
    }
    FLAMEGPU->setVariable<unsigned int>("settled", 1u);
    return flamegpu::ALIVE;
}

// Another round while anyone is unsettled; each round's claims outrank the last round's.
FLAMEGPU_EXIT_CONDITION(movement_settled) {
    if (FLAMEGPU->agent("citizen").count<unsigned int>("settled", 0u) == 0) return flamegpu::EXIT;
    const unsigned int round = FLAMEGPU->environment.getProperty<unsigned int>("round") + 1;
    if (round > MAX_ROUNDS) throw RoundLimitError("movement needed more than " + std::to_string(MAX_ROUNDS) + " rounds");
    FLAMEGPU->environment.setProperty<unsigned int>("round", round);
    return flamegpu::CONTINUE;
}

#endif  // SRC_MOVEMENT_CUH_
