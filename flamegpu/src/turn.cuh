// One agent's turn, exactly as Python's Model.step runs it for one agent (spec 2026-10-25-gpu-full-parity, section
// 2): move to the deferred-acceptance target, harvest, metabolise, count neighbours. The scheduler has given the turn
// sole use of its footprint, so it reads and writes the store directly. Included only by model.cu (via turns.cuh).
#ifndef SRC_TURN_CUH_
#define SRC_TURN_CUH_

#include "movement.cuh"
#include "store.h"

template <typename API>
__device__ void take_turn(API* FLAMEGPU, const Store& s, unsigned int row) {
    const auto& env = FLAMEGPU->environment;
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    auto occupied = env.template getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    auto sugar = env.template getMacroProperty<float, MAX_CELLS>("sugar");
    auto pollution = env.template getMacroProperty<float, MAX_CELLS>("pollution");
    const bool polluting = env.template getProperty<unsigned int>("pollution_active") != 0u;

    // Move (Python movement.move after the choice, and Model.move_agent).
    const unsigned int start = s.start[row], target = s.target[row];
    if (target != start) {
        s.site_row[start] = -1;
        s.site_row[target] = static_cast<int>(row);
        occupied[start].exchange(0u);
        occupied[target].exchange(1u);
        const int nx = static_cast<int>(target % static_cast<unsigned int>(w));
        const int ny = static_cast<int>(target / static_cast<unsigned int>(w));
        s.disp_x[row] += torus_step(nx - s.x[row], w);
        s.disp_y[row] += torus_step(ny - s.y[row], h);
        s.x[row] = nx;
        s.y[row] = ny;
        s.moved[row] = 1u;
    }
    // Harvest, with production pollution (p.47).
    const float harvest = sugar[target].exchange(0.0f);
    s.sugar[row] += static_cast<double>(harvest);
    if (polluting) pollution[target] += env.template getProperty<float>("pollution_alpha") * harvest;
    // Metabolism, with consumption pollution; death when sugar runs out (p.25).
    const int metabolism = s.metabolism[row];
    s.sugar[row] -= static_cast<double>(metabolism);
    if (polluting) pollution[target] += env.template getProperty<float>("pollution_beta") * static_cast<float>(metabolism);
    if (s.sugar[row] <= 0.0) {
        s.dead[row] = 1u;
        s.site_row[target] = -1;
        occupied[target].exchange(0u);
        return;
    }
    // Neighbours: the four von Neumann sites as they stand now (p.39).
    const int x = s.x[row], y = s.y[row];
    unsigned int n = 0;
    for (int d = 0; d < 4; ++d) {
        n += s.site_row[wrap(x + MOVE_DX[d], w) + wrap(y + MOVE_DY[d], h) * w] >= 0 ? 1u : 0u;
    }
    s.neighbors[row] = n;
}

#endif  // SRC_TURN_CUH_
