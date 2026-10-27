// Movement rule M in parallel: deferred acceptance over the period's order inside a sub-model, then one commit
// (spec 2026-10-25-gpu-sequential-semantics, section 2). Every site prefers the agent earliest in the order, so the
// rounds end where Python's one-agent-at-a-time rule ends over the sites free at the period's start.
// Included only by model.cu.
#ifndef SRC_MOVEMENT_CUH_
#define SRC_MOVEMENT_CUH_

#include "host_state.h"
#include "looks.cuh"
#include "model.h"
#include "welfare.h"

// Directions in the Python project's VON_NEUMANN order: east, west, north, south.
__device__ __constant__ int MOVE_DX[4] = {1, -1, 0, 0};
__device__ __constant__ int MOVE_DY[4] = {0, 0, 1, -1};

constexpr unsigned int MAX_ROUNDS = 65535;

// Movement states (the citizen's "settled" variable during the movement sub-model).
constexpr unsigned int MOVE_SCAN = 0u;     // must scan: the period's first round, or displaced from its site
constexpr unsigned int MOVE_HOLD = 1u;     // holds a bid on its target
constexpr unsigned int MOVE_STAY = 2u;     // stays put: its own site is its best available, which only shrinks
constexpr unsigned int MOVE_PENDING = 3u;  // chose a new target this round; bid places the bid

// The period's order: priority (32 bits) | agent id (32 bits). Larger is earlier in the order, and the largest key
// at a site wins it. Never 0, since ids start at 1.
__device__ __forceinline__ uint64_t order_key(unsigned int priority, flamegpu::id_t id) {
    return (static_cast<uint64_t>(priority) << 32) | static_cast<uint64_t>(id);
}

__device__ __forceinline__ int wrap(int v, int n) { return ((v % n) + n) % n; }

// A step of d along a ring of n sites, taken the shortest way: Python's (d + n // 2) % n - n // 2.
__device__ __forceinline__ int torus_step(int d, int n) { return wrap(d + n / 2, n) - n / 2; }


// Propose (reads occupied, sugar, pollution, claim): the nearest best site in view that was free at the period's
// start (occupied does not change during the sub-model) and that no earlier agent holds, scanned as candidate_sites
// does: own site at distance 0, then the four directions in the period's order out to vision, every site or with a
// look stride one centred look per whole stride (looks.cuh; a repeated look changes no choice). Agents that stay, or
// whose bid still stands, have nothing to do.
FLAMEGPU_AGENT_FUNCTION(propose, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int state = FLAMEGPU->getVariable<unsigned int>("settled");
    if (state == MOVE_STAY) return flamegpu::ALIVE;
    const uint64_t key = order_key(FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID());
    auto claim = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("claim");
    if (state == MOVE_HOLD &&
        static_cast<uint64_t>(claim[FLAMEGPU->getVariable<unsigned int>("target")]) == key) {
        return flamegpu::ALIVE;
    }
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
    const int x = FLAMEGPU->getVariable<int>("x");
    const int y = FLAMEGPU->getVariable<int>("y");
    const int vision = FLAMEGPU->getVariable<int>("vision");
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
    auto spice = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("spice");

    // The site's score: sugar / (1 + pollution) in float (p.47 fn 37), or with spice Python's welfare_scorer in double,
    // from the holdings at the start of the period (spec section 8, difference 3): W(max(w1 - phi m1, 0) + s/(1+p),
    // max(w2 - phi m2, 0) + c/(1+p)), eq. 6's foresight and eq. 5's cultural fraction. A float score widened to double
    // keeps every comparison as it was.
    const bool with_spice = FLAMEGPU->environment.getProperty<unsigned int>("spice") != 0u;
    double base1 = 0, base2 = 0, f = 0.5;
    int metabolism = 0, spice_metabolism = 0;
    if (with_spice) {
        metabolism = FLAMEGPU->getVariable<int>("metabolism");
        spice_metabolism = FLAMEGPU->getVariable<int>("spice_metabolism");
        const double phi = static_cast<double>(FLAMEGPU->getVariable<int>("foresight"));
        base1 = fmax(FLAMEGPU->getVariable<double>("sugar") - phi * metabolism, 0.0);
        base2 = fmax(FLAMEGPU->getVariable<double>("spice") - phi * spice_metabolism, 0.0);
        f = preference_fraction(FLAMEGPU->getVariable<uint64_t>("tags"),
                                static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("tag_length")),
                                FLAMEGPU->environment.getProperty<unsigned int>("cultural_preferences") != 0u);
    }
    auto score_at = [&](unsigned int site) -> double {
        if (!with_spice) return static_cast<double>(static_cast<float>(sugar[site]) / (1.0f + static_cast<float>(pollution[site])));
        const double devalue = 1.0 + static_cast<double>(static_cast<float>(pollution[site]));
        return welfare(static_cast<double>(metabolism), spice_metabolism, f,
                       base1 + static_cast<double>(static_cast<float>(sugar[site])) / devalue,
                       base2 + static_cast<double>(static_cast<float>(spice[site])) / devalue);
    };

    const unsigned int own = static_cast<unsigned int>(x + y * w);
    unsigned int best = own;
    int best_dist = 0;
    double best_score = score_at(own);

    const unsigned int dir_order = FLAMEGPU->getVariable<unsigned int>("dir_order");  // the period's (start_period)
    const int stride = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("look_stride"));
    const unsigned int look_seed = stride > 1 ? FLAMEGPU->getVariable<unsigned int>("look_seed") : 0u;
    for (int k = 0; k < 4; ++k) {
        const int d = static_cast<int>((dir_order >> (2 * k)) & 3u);
        const int looks = vision / stride;  // validate(): vision is in whole strides
        for (int i = 0; i < looks; ++i) {
            const int dist = stride == 1 ? i + 1 : look_distance(look_seed, d, i, stride);
            const unsigned int site =
                static_cast<unsigned int>(wrap(x + MOVE_DX[d] * dist, w) + wrap(y + MOVE_DY[d] * dist, h) * w);
            if (static_cast<unsigned int>(occupied[site])) continue;  // check occupancy before reading the site
            if (static_cast<uint64_t>(claim[site]) > key) continue;  // an earlier agent holds it
            const double score = score_at(site);
            if (score > best_score || (score == best_score && dist < best_dist)) {
                best = site;
                best_dist = dist;
                best_score = score;
            }
        }
    }
    FLAMEGPU->setVariable<unsigned int>("target", best);
    FLAMEGPU->setVariable<unsigned int>("settled", best == own ? MOVE_STAY : MOVE_PENDING);
    return flamegpu::ALIVE;
}

// Bid (writes claim, bids): a site keeps the largest key, the earliest agent, across rounds. A later holder it
// displaces finds out in the next round's propose and chooses again.
FLAMEGPU_AGENT_FUNCTION(bid, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<unsigned int>("settled") != MOVE_PENDING) return flamegpu::ALIVE;
    auto claim = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("claim");
    claim[FLAMEGPU->getVariable<unsigned int>("target")].max(
        order_key(FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID()));
    auto bids = FLAMEGPU->environment.getMacroProperty<unsigned int>("bids");
    ++bids;
    FLAMEGPU->setVariable<unsigned int>("settled", MOVE_HOLD);
    return flamegpu::ALIVE;
}

// Another round while the last one placed a bid: only a bid can displace a holder. Every bid raises a site's claim,
// so the rounds end.
FLAMEGPU_EXIT_CONDITION(movement_settled) {
    auto bids = FLAMEGPU->environment.getMacroProperty<unsigned int>("bids");
    const unsigned int placed = bids;
    bids = 0u;
    if (placed == 0u) return flamegpu::EXIT;
    const unsigned int round = FLAMEGPU->environment.getProperty<unsigned int>("round") + 1;
    if (round > MAX_ROUNDS) throw RoundLimitError("movement needed more than " + std::to_string(MAX_ROUNDS) + " rounds");
    FLAMEGPU->environment.setProperty<unsigned int>("round", round);
    return flamegpu::CONTINUE;
}

// Commit (writes occupied, sugar, pollution, left, arrived), after the sub-model: holders move to their targets and
// harvest them; stayers harvest their own sites. Everyone records its order key where it started (left) and where it
// ends (arrived), for count_neighbors. Targets were free at the start and are distinct, so no two agents write a site.
FLAMEGPU_AGENT_FUNCTION(commit_move, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    const unsigned int own = static_cast<unsigned int>(FLAMEGPU->getVariable<int>("x")) +
                             static_cast<unsigned int>(FLAMEGPU->getVariable<int>("y")) * w;
    const bool moving = FLAMEGPU->getVariable<unsigned int>("settled") == MOVE_HOLD;
    const unsigned int site = moving ? FLAMEGPU->getVariable<unsigned int>("target") : own;
    const uint64_t key = order_key(FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID());
    auto left = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("left");
    auto arrived = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("arrived");
    left[own].exchange(key);
    arrived[site].exchange(key);
    if (moving) {
        auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
        occupied[own].exchange(0u);
        occupied[site].exchange(1u);
        const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
        const int nx = static_cast<int>(site % w), ny = static_cast<int>(site / w);
        // Net displacement, the shortest way round the torus (Python Model.move_agent).
        FLAMEGPU->setVariable<int>("disp_x", FLAMEGPU->getVariable<int>("disp_x") +
                                                 torus_step(nx - FLAMEGPU->getVariable<int>("x"), static_cast<int>(w)));
        FLAMEGPU->setVariable<int>("disp_y", FLAMEGPU->getVariable<int>("disp_y") +
                                                 torus_step(ny - FLAMEGPU->getVariable<int>("y"), h));
        FLAMEGPU->setVariable<int>("x", nx);
        FLAMEGPU->setVariable<int>("y", ny);
        FLAMEGPU->setVariable<unsigned int>("moved", 1u);
    }
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    const float harvest = sugar[site].exchange(0.0f);
    FLAMEGPU->setVariable<double>("sugar", FLAMEGPU->getVariable<double>("sugar") + static_cast<double>(harvest));
    if (FLAMEGPU->environment.getProperty<unsigned int>("spice")) {  // and the site's spice (Python move)
        auto spice = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("spice");
        FLAMEGPU->setVariable<double>("spice", FLAMEGPU->getVariable<double>("spice") +
                                                   static_cast<double>(spice[site].exchange(0.0f)));
    }
    if (FLAMEGPU->environment.getProperty<unsigned int>("pollution_active")) {
        auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
        pollution[site] += FLAMEGPU->environment.getProperty<float>("pollution_alpha") * harvest;  // production (p.47)
    }
    return flamegpu::ALIVE;
}

#endif  // SRC_MOVEMENT_CUH_
