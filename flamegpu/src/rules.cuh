// The per-period citizen and cell functions outside movement (design: One period, steps 1, 3, 4, 7, 8).
// Included only by model.cu.
#ifndef SRC_RULES_CUH_
#define SRC_RULES_CUH_

#include "model.h"
#include "movement.cuh"

// Start of period: a fresh random priority stands in for the period's random order.
FLAMEGPU_AGENT_FUNCTION(start_period, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int priority = static_cast<unsigned int>(FLAMEGPU->random.uniform<float>() * 1048576.0f);
    FLAMEGPU->setVariable<unsigned int>("priority", min(priority, 0xFFFFFu));
    FLAMEGPU->setVariable<unsigned int>("settled", 0u);
    FLAMEGPU->setVariable<unsigned int>("moved", 0u);
    return flamegpu::ALIVE;
}

// Occupied von Neumann sites around the agent after everyone has moved (reads occupied).
FLAMEGPU_AGENT_FUNCTION(count_neighbors, flamegpu::MessageNone, flamegpu::MessageNone) {
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
    const int x = FLAMEGPU->getVariable<int>("x");
    const int y = FLAMEGPU->getVariable<int>("y");
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    unsigned int n = 0;
    for (int d = 0; d < 4; ++d) {
        n += static_cast<unsigned int>(occupied[wrap(x + MOVE_DX[d], w) + wrap(y + MOVE_DY[d], h) * w]);
    }
    FLAMEGPU->setVariable<unsigned int>("neighbors", n);
    return flamegpu::ALIVE;
}

// Metabolism (p.25) with consumption pollution (p.47), then aging; death frees the site
// (writes occupied, pollution, deaths).
FLAMEGPU_AGENT_FUNCTION(metabolize_and_age, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    const unsigned int site = static_cast<unsigned int>(FLAMEGPU->getVariable<int>("x")) +
                              static_cast<unsigned int>(FLAMEGPU->getVariable<int>("y")) * w;
    const int metabolism = FLAMEGPU->getVariable<int>("metabolism");
    const float sugar = FLAMEGPU->getVariable<float>("sugar") - static_cast<float>(metabolism);
    FLAMEGPU->setVariable<float>("sugar", sugar);
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
        return flamegpu::DEAD;
    }
    return flamegpu::ALIVE;
}

// Cell layer A (reads sugar, capacity, pollution; writes sugar_next, pollution_next): growback G_alpha / G_inf or
// seasonal S_alpha,beta,gamma (p.44), and diffusion D_alpha (p.48).
FLAMEGPU_AGENT_FUNCTION(cell_grow, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int i = FLAMEGPU->getIndex();  // the site index (make_cells)
    const int w = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("width"));
    const int h = static_cast<int>(FLAMEGPU->environment.getProperty<unsigned int>("height"));
    const int x = static_cast<int>(i) % w, y = static_cast<int>(i) / w;
    const unsigned int t = FLAMEGPU->environment.getProperty<unsigned int>("t");
    auto capacity = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("capacity");
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
    sugar_next[i].exchange(fminf(static_cast<float>(sugar[i]) + rate, static_cast<float>(static_cast<unsigned int>(capacity[i]))));

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

// Cell layer B (reads sugar_next, pollution_next; writes sugar, pollution, claim): copy back, clear claims.
FLAMEGPU_AGENT_FUNCTION(cell_commit, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int i = FLAMEGPU->getIndex();  // the site index (make_cells)
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
    auto sugar_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar_next");
    auto pollution_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution_next");
    auto claim = FLAMEGPU->environment.getMacroProperty<uint64_t, MAX_CELLS>("claim");
    sugar[i].exchange(static_cast<float>(sugar_next[i]));
    pollution[i].exchange(static_cast<float>(pollution_next[i]));
    claim[i].min(uint64_t{0});
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
