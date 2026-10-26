// The per-period citizen and cell functions outside movement (design: One period, steps 1, 3, 4, 7, 8).
// Included only by model.cu.
#ifndef SRC_RULES_CUH_
#define SRC_RULES_CUH_

#include "model.h"
#include "movement.cuh"
#include "store.h"
#include "tribe.h"

// Initialisation, on the device so no host function copies a site-sized macro property (xl design, section 3).
// Cell layer (writes sugar): in the first period only, every site starts at capacity (p.21).
FLAMEGPU_AGENT_FUNCTION(cell_initialise, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (!FLAMEGPU->environment.getProperty<unsigned int>("initialising")) return flamegpu::ALIVE;
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    sugar[FLAMEGPU->getIndex()].exchange(static_cast<float>(FLAMEGPU->getVariable<unsigned int>("capacity")));
    return flamegpu::ALIVE;
}

// Citizen layer (writes occupied): every citizen marks its site. Run before the first period's movement, for the
// founders; newcomers mark their own sites in place_newcomer.
FLAMEGPU_AGENT_FUNCTION(occupy_site, flamegpu::MessageNone, flamegpu::MessageNone) {
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    occupied[FLAMEGPU->getVariable<int>("x") + FLAMEGPU->getVariable<int>("y") * w].exchange(1u);
    return flamegpu::ALIVE;
}

// Start of period: the period's order, drawn once (spec 2026-10-25-gpu-sequential-semantics, section 1). A 32-bit
// priority (through the 64-bit draw, so every value is reachable) stands in for Python's random order, and dir_order
// fixes the scan's direction order for the period, as Python's candidate_sites draws it once.
FLAMEGPU_AGENT_FUNCTION(start_period, flamegpu::MessageNone, flamegpu::MessageNone) {
    FLAMEGPU->setVariable<unsigned int>(
        "priority", static_cast<unsigned int>(FLAMEGPU->random.uniform<uint64_t>(0, 0xFFFFFFFFull)));
    int order[4] = {0, 1, 2, 3};
    for (int i = 3; i > 0; --i) {  // Fisher-Yates; uniform(0, i) can return i + 1 at the float endpoint
        const int j = min(FLAMEGPU->random.uniform<int>(0, i), i);
        const int tmp = order[i];
        order[i] = order[j];
        order[j] = tmp;
    }
    FLAMEGPU->setVariable<unsigned int>("dir_order", static_cast<unsigned int>(order[0] | order[1] << 2 |
                                                                                order[2] << 4 | order[3] << 6));
    // One look per period (xl design, section 2a): the strided scan's offsets all derive from this seed, so a rescan
    // in a later movement round sees the same sites. Drawn only above stride 1, so regular random streams stay.
    if (FLAMEGPU->environment.getProperty<unsigned int>("look_stride") > 1u) {
        FLAMEGPU->setVariable<unsigned int>(
            "look_seed", static_cast<unsigned int>(FLAMEGPU->random.uniform<uint64_t>(0, 0xFFFFFFFFull)));
    }
    FLAMEGPU->setVariable<unsigned int>("settled", 0u);
    FLAMEGPU->setVariable<unsigned int>("moved", 0u);
    return flamegpu::ALIVE;
}

// The occupied von Neumann sites around the agent as they stand at its turn in the period's order, as Python counts
// right after the agent's own move and metabolism (reads left, arrived): an earlier agent at the site it ended on,
// unless it starved; a later agent at the site it started from, since it has not moved yet. Run after metabolism.
FLAMEGPU_AGENT_FUNCTION(count_neighbors, flamegpu::MessageNone, flamegpu::MessageNone) {
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
    const int x = FLAMEGPU->getVariable<int>("x");
    const int y = FLAMEGPU->getVariable<int>("y");
    if (x < 0) {  // a newcomer born this period, not yet placed: Python spawns it after every turn, so it counts 0
        FLAMEGPU->setVariable<unsigned int>("neighbors", 0u);
        return flamegpu::ALIVE;
    }
    const uint64_t key = order_key(FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID());
    auto left = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("left");
    auto arrived = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("arrived");
    unsigned int n = 0;
    for (int d = 0; d < 4; ++d) {
        const unsigned int s = static_cast<unsigned int>(wrap(x + MOVE_DX[d], w) + wrap(y + MOVE_DY[d], h) * w);
        const uint64_t a = arrived[s];
        const uint64_t l = left[s];
        n += (a > key || (l != 0u && l < key)) ? 1u : 0u;
    }
    FLAMEGPU->setVariable<unsigned int>("neighbors", n);
    return flamegpu::ALIVE;
}

// A uniform integer on lo..hi inclusive through the 64-bit draw (uniform<int> goes through a float and can return
// hi + 1 at the endpoint).
template <typename API>
__device__ __forceinline__ int draw_between(API* FLAMEGPU, int lo, int hi) {
    return lo + static_cast<int>(FLAMEGPU->random.template uniform<uint64_t>(0ull, static_cast<uint64_t>(hi - lo)));
}

// `bits` uniform random bits (at most 63), bit 0 first, drawn 32 at a time.
template <typename API>
__device__ __forceinline__ uint64_t random_bits(API* FLAMEGPU, int bits) {
    uint64_t out = 0;
    for (int done = 0; done < bits; done += 32) {
        const int k = min(32, bits - done);
        out |= FLAMEGPU->random.template uniform<uint64_t>(0ull, (1ull << k) - 1ull) << done;
    }
    return out;
}

// Every citizen variable of a new agent set to the model's default (model.cu, describe_model). Each agent output calls
// this first rather than leaving any variable to FLAME GPU: rc.5 lays the new agents' defaults out unaligned
// (CUDAScatter::broadcastInit_async against CUDAAgent::mapNewRuntimeVariables_async's 8-byte alignment), so in an
// odd-sized output the last agents got the next variable's default, or uninitialised memory.
__device__ __forceinline__ void init_citizen_out(flamegpu::DeviceAPI<flamegpu::MessageNone, flamegpu::MessageNone>* FLAMEGPU) {
    auto& out = FLAMEGPU->agent_out;  // device setVariable takes literal names only
    out.setVariable<int>("x", 0);
    out.setVariable<int>("y", 0);
    out.setVariable<int>("vision", 0);
    out.setVariable<int>("metabolism", 0);
    out.setVariable<int>("age", 0);
    out.setVariable<int>("max_age", 0);
    out.setVariable<int>("disp_x", 0);
    out.setVariable<int>("disp_y", 0);
    out.setVariable<double>("sugar", 0.0);
    out.setVariable<double>("initial_sugar", 0.0);
    out.setVariable<uint64_t>("tags", 0ull);
    out.setVariable<uint64_t>("death_key", 0ull);
    out.setVariable<unsigned int>("sex", SEX_NONE);
    out.setVariable<int>("fertility_start", NO_FERTILITY_START);
    out.setVariable<int>("fertility_end", NO_FERTILITY_END);
    out.setVariable<unsigned int>("parent_a", NO_UID);
    out.setVariable<unsigned int>("parent_b", NO_UID);
    out.setVariable<unsigned int>("uid", 0u);
    out.setVariable<unsigned int>("n_children", 0u);
    out.setVariable<unsigned int>("n_friends", 0u);
    out.setVariable<unsigned int>("moved", 0u);
    out.setVariable<unsigned int>("neighbors", 0u);
    out.setVariable<unsigned int>("settled", 0u);
    out.setVariable<unsigned int>("priority", 0u);
    out.setVariable<unsigned int>("target", 0u);
    out.setVariable<unsigned int>("look_seed", 0u);
    out.setVariable<unsigned int>("dir_order", 0u);
    out.setVariable<unsigned int>("row", 0u);
    out.setVariable<unsigned int>("nc_slot", 0u);
    out.setVariable<unsigned int>("dying", 0u);
    for (unsigned int f = 0; f < MAX_FRIENDS; ++f) {
        out.setVariable<unsigned int, MAX_FRIENDS>("friend_uid", f, 0u);
        out.setVariable<unsigned int, MAX_FRIENDS>("friend_dist", f, 0u);
    }
}

// R[a,b] (p.32), first half: the newcomer replacing a citizen that dies, drawn with the dying citizen's random
// stream as Python's spawn_random_agent draws it (uniform on each inclusive range; vision in whole look strides).
// It is unplaced (x = y = -1) until place_newcomer; age 0 and every other variable at its default, as before. With
// same-tribe replacement (p.86) its tags are redrawn until its tribe is the dead agent's, as Python's random_tags.
__device__ __forceinline__ void output_newcomer(flamegpu::DeviceAPI<flamegpu::MessageNone, flamegpu::MessageNone>* FLAMEGPU,
                                                uint64_t death_key, uint64_t dead_tags) {
    const auto& env = FLAMEGPU->environment;
    const int stride = static_cast<int>(env.getProperty<unsigned int>("look_stride"));
    init_citizen_out(FLAMEGPU);
    FLAMEGPU->agent_out.setVariable<int>("x", -1);
    FLAMEGPU->agent_out.setVariable<int>("y", -1);
    FLAMEGPU->agent_out.setVariable<int>(
        "vision", stride * FLAMEGPU->random.uniform<int>(env.getProperty<int>("vision_lo") / stride,
                                                         env.getProperty<int>("vision_hi") / stride));
    FLAMEGPU->agent_out.setVariable<int>(
        "metabolism", FLAMEGPU->random.uniform<int>(env.getProperty<int>("metabolism_lo"), env.getProperty<int>("metabolism_hi")));
    const double sugar = static_cast<double>(FLAMEGPU->random.uniform<int>(
        env.getProperty<int>("endowment_lo"), env.getProperty<int>("endowment_hi")));
    FLAMEGPU->agent_out.setVariable<double>("sugar", sugar);
    FLAMEGPU->agent_out.setVariable<double>("initial_sugar", sugar);
    FLAMEGPU->agent_out.setVariable<int>(
        "max_age", FLAMEGPU->random.uniform<int>(env.getProperty<int>("max_age_lo"), env.getProperty<int>("max_age_hi")));
    FLAMEGPU->agent_out.setVariable<int>("age", 0);
    // Chapter III draws after Chapter II's, as Python's _spawn_at (spec 2026-10-25-gpu-full-parity, Task 2).
    const int tag_length = static_cast<int>(env.getProperty<unsigned int>("tag_length"));
    if (tag_length) {
        uint64_t tags = random_bits(FLAMEGPU, tag_length);
        if (env.getProperty<unsigned int>("same_tribe")) {
            while (is_blue(tags, tag_length) != is_blue(dead_tags, tag_length)) tags = random_bits(FLAMEGPU, tag_length);
        }
        FLAMEGPU->agent_out.setVariable<uint64_t>("tags", tags);
    }
    if (env.getProperty<unsigned int>("sex")) {
        const bool female = draw_between(FLAMEGPU, 0, 1) == 0;
        FLAMEGPU->agent_out.setVariable<unsigned int>("sex", female ? SEX_F : SEX_M);
        FLAMEGPU->agent_out.setVariable<int>(
            "fertility_start", draw_between(FLAMEGPU, env.getProperty<int>("fertility_start_lo"),
                                            env.getProperty<int>("fertility_start_hi")));
        FLAMEGPU->agent_out.setVariable<int>(
            "fertility_end", female ? draw_between(FLAMEGPU, env.getProperty<int>("female_fertility_end_lo"),
                                                   env.getProperty<int>("female_fertility_end_hi"))
                                    : draw_between(FLAMEGPU, env.getProperty<int>("male_fertility_end_lo"),
                                                   env.getProperty<int>("male_fertility_end_hi")));
    }
    // Its uid comes after placement, in the order of the deaths (turns.cuh, newcomer_post / newcomer_take).
    FLAMEGPU->agent_out.setVariable<uint64_t>("death_key", death_key);
}

// Metabolism (p.25) with consumption pollution (p.47), then aging; death frees the site and, with replacement,
// outputs the newcomer (writes occupied, pollution, deaths).
FLAMEGPU_AGENT_FUNCTION(metabolize_and_age, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    const unsigned int site = static_cast<unsigned int>(FLAMEGPU->getVariable<int>("x")) +
                              static_cast<unsigned int>(FLAMEGPU->getVariable<int>("y")) * w;
    const int metabolism = FLAMEGPU->getVariable<int>("metabolism");
    const double sugar = FLAMEGPU->getVariable<double>("sugar") - static_cast<double>(metabolism);
    FLAMEGPU->setVariable<double>("sugar", sugar);
    if (FLAMEGPU->environment.getProperty<unsigned int>("pollution_active")) {
        auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
        pollution[site] += FLAMEGPU->environment.getProperty<float>("pollution_beta") * static_cast<float>(metabolism);
    }
    const int age = FLAMEGPU->getVariable<int>("age") + 1;
    FLAMEGPU->setVariable<int>("age", age);
    if (sugar <= 0.0f || age >= FLAMEGPU->getVariable<int>("max_age")) {
        auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
        auto deaths = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
        occupied[site].exchange(0u);
        ++deaths;
        // Python removes a starved agent at its turn, so later agents don't count it; an agent dying of old age is
        // removed only at the end of the period, so everyone still counts it (count_neighbors).
        if (sugar <= 0.0f) {
            auto arrived = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("arrived");
            arrived[site].exchange(uint64_t{0});
        }
        if (FLAMEGPU->environment.getProperty<unsigned int>("replacement")) {
            // Python spawns newcomers for the starved first, in the period's order, then for old age by uid.
            const uint64_t key = order_key(FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID());
            output_newcomer(FLAMEGPU, sugar <= 0.0 ? starved_key(~key >> 1)
                                                    : old_age_key(FLAMEGPU->getVariable<unsigned int>("uid")),
                            FLAMEGPU->getVariable<uint64_t>("tags"));
        }
        return flamegpu::DEAD;
    }
    return flamegpu::ALIVE;
}

// R[a,b] (p.32), second half (writes occupied, by CAS only): each unplaced newcomer claims a site drawn uniformly
// from all sites until it finds an empty one. The draws treat every empty site alike, so the newcomers' sites are a
// uniformly random set of empty sites, as Python's one-after-another draws give. There are always at least as many
// empty sites as newcomers (each death freed its own), and after PLACE_TRIES misses a newcomer scans on from its
// last draw, so the claim always ends (spec 2026-10-25, section 2).
constexpr unsigned int PLACE_TRIES = 4096;
FLAMEGPU_AGENT_FUNCTION(place_newcomer, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<int>("x") >= 0) return flamegpu::ALIVE;
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    const unsigned int cells = w * FLAMEGPU->environment.getProperty<unsigned int>("height");
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    unsigned int site = 0;
    bool placed = false;
    for (unsigned int k = 0; k < PLACE_TRIES && !placed; ++k) {
        // The 64-bit draw goes through a double; uniform<unsigned int> uses a 24-bit float, which reaches sites
        // unevenly in large worlds and never reaches some beyond 2^24 sites.
        site = static_cast<unsigned int>(FLAMEGPU->random.uniform<uint64_t>(0ull, cells - 1ull));
        placed = occupied[site].CAS(0u, 1u) == 0u;
    }
    while (!placed) {
        site = site + 1u == cells ? 0u : site + 1u;
        placed = occupied[site].CAS(0u, 1u) == 0u;
    }
    FLAMEGPU->setVariable<int>("x", static_cast<int>(site % w));
    FLAMEGPU->setVariable<int>("y", static_cast<int>(site / w));
    return flamegpu::ALIVE;
}

// Cell layer A (reads sugar, pollution; writes sugar_next, pollution_next): growback G_alpha / G_inf or
// seasonal S_alpha,beta,gamma (p.44), and diffusion D_alpha (p.48).
FLAMEGPU_AGENT_FUNCTION(cell_grow, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int i = FLAMEGPU->getIndex();  // the site index (make_cells)
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
    const int x = static_cast<int>(i) % w, y = static_cast<int>(i) / w;
    const unsigned int t = FLAMEGPU->environment.getProperty<unsigned int>("t");
    const unsigned int capacity = FLAMEGPU->getVariable<unsigned int>("capacity");
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
    auto sugar_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar_next");
    auto pollution_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution_next");

    float rate = FLAMEGPU->environment.getProperty<float>("growback_rate");  // inf gives capacity (G_inf)
    const unsigned int gamma = FLAMEGPU->environment.getProperty<unsigned int>("seasons_gamma");
    if (gamma) {
        // Summer north while t mod 2*gamma < gamma (p.44 fn 33); the north is y >= height / 2.
        const bool summer_north = t % (2 * gamma) < gamma;
        const bool north = y >= h / 2;
        if (north != summer_north) {
            const unsigned int beta = FLAMEGPU->environment.getProperty<unsigned int>("seasons_beta");
            if (FLAMEGPU->environment.getProperty<unsigned int>("winter_pulse")) {
                rate = t % beta == 0 ? rate : 0.0f;  // alpha on periods with t % beta == 0
            } else {
                rate = rate / static_cast<float>(beta);  // alpha / beta every period
            }
        }
    }
    sugar_next[i].exchange(fminf(static_cast<float>(sugar[i]) + rate, static_cast<float>(capacity)));

    float p = pollution[i];
    if (FLAMEGPU->environment.getProperty<unsigned int>("diffuse_now")) {
        // The mean of the four von Neumann neighbours, the site's own value left out (Python Landscape.diffuse).
        p = (static_cast<float>(pollution[wrap(x - 1, w) + y * w]) + static_cast<float>(pollution[wrap(x + 1, w) + y * w]) +
             static_cast<float>(pollution[x + wrap(y - 1, h) * w]) + static_cast<float>(pollution[x + wrap(y + 1, h) * w])) /
            4.0f;
    }
    pollution_next[i].exchange(p);
    return flamegpu::ALIVE;
}

// Cell layer B (reads sugar_next, pollution_next; writes sugar, pollution, claim, left, arrived): copy back, and
// clear the period's order keys so the next period starts empty.
FLAMEGPU_AGENT_FUNCTION(cell_commit, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int i = FLAMEGPU->getIndex();  // the site index (make_cells)
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
    auto sugar_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar_next");
    auto pollution_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution_next");
    auto claim = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("claim");
    auto left = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("left");
    auto arrived = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("arrived");
    sugar[i].exchange(static_cast<float>(sugar_next[i]));
    pollution[i].exchange(static_cast<float>(pollution_next[i]));
    claim[i].min(uint64_t{0});
    left[i].min(uint64_t{0});
    arrived[i].min(uint64_t{0});
    return flamegpu::ALIVE;
}

// The pollution_diffusion sub-model: the passes of D after cell_grow's first, each the mean of the four neighbours of
// the previous pass (Python's loop of Landscape.diffuse). It runs one step every period; with no extra passes due,
// both layers return at once.
__device__ inline bool extra_pass_due(flamegpu::DeviceAPI<flamegpu::MessageNone, flamegpu::MessageNone>* api) {
    return api->environment.getProperty<unsigned int>("diffusion_pass") <
           api->environment.getProperty<unsigned int>("extra_passes");
}

// Diffusion layer A (reads pollution; writes pollution_next).
FLAMEGPU_AGENT_FUNCTION(diffuse, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (!extra_pass_due(FLAMEGPU)) return flamegpu::ALIVE;
    const unsigned int i = FLAMEGPU->getIndex();  // the site index (make_cells)
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
    const int x = static_cast<int>(i) % w, y = static_cast<int>(i) / w;
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
    auto pollution_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution_next");
    // The same arithmetic as cell_grow's pass, so every pass rounds alike.
    const float p = (static_cast<float>(pollution[wrap(x - 1, w) + y * w]) + static_cast<float>(pollution[wrap(x + 1, w) + y * w]) +
                     static_cast<float>(pollution[x + wrap(y - 1, h) * w]) + static_cast<float>(pollution[x + wrap(y + 1, h) * w])) /
                    4.0f;
    pollution_next[i].exchange(p);
    return flamegpu::ALIVE;
}

// Diffusion layer B (reads pollution_next; writes pollution).
FLAMEGPU_AGENT_FUNCTION(diffuse_commit, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (!extra_pass_due(FLAMEGPU)) return flamegpu::ALIVE;
    const unsigned int i = FLAMEGPU->getIndex();
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
    auto pollution_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution_next");
    pollution[i].exchange(static_cast<float>(pollution_next[i]));
    return flamegpu::ALIVE;
}

// Another pass while extra passes remain this period.
FLAMEGPU_EXIT_CONDITION(diffusion_done) {
    const unsigned int pass = FLAMEGPU->environment.getProperty<unsigned int>("diffusion_pass") + 1;
    FLAMEGPU->environment.setProperty<unsigned int>("diffusion_pass", pass);
    return pass >= FLAMEGPU->environment.getProperty<unsigned int>("extra_passes") ? flamegpu::EXIT : flamegpu::CONTINUE;
}

#endif  // SRC_RULES_CUH_
