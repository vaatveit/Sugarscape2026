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

// Cell layer A (reads sugar, capacity, pollution; writes sugar_next, pollution_next): growback G_alpha / G_inf.
FLAMEGPU_AGENT_FUNCTION(cell_grow, flamegpu::MessageNone, flamegpu::MessageNone) {
    const unsigned int i = FLAMEGPU->getIndex();  // the site index (make_cells)
    auto capacity = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("capacity");
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto pollution = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution");
    auto sugar_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar_next");
    auto pollution_next = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("pollution_next");
    const float rate = FLAMEGPU->environment.getProperty<float>("growback_rate");  // inf gives capacity (G_inf)
    sugar_next[i].exchange(fminf(static_cast<float>(sugar[i]) + rate, static_cast<float>(static_cast<unsigned int>(capacity[i]))));
    pollution_next[i].exchange(static_cast<float>(pollution[i]));
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

#endif  // SRC_RULES_CUH_
