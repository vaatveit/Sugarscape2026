// One agent's turn, exactly as Python's Model.step runs it for one agent (spec 2026-10-25-gpu-full-parity, section
// 2): move to the deferred-acceptance target (or by combat), harvest, metabolise, count neighbours, then S, K, T, L. The
// scheduler has given the turn sole use of its footprint, so it reads and writes the store directly. Included only by
// model.cu (via turns.cuh).
#ifndef SRC_TURN_CUH_
#define SRC_TURN_CUH_

#include "combat.cuh"
#include "credit.cuh"
#include "culture.cuh"
#include "heirs.cuh"
#include "movement.cuh"
#include "sex.cuh"
#include "store.h"
#include "trade.cuh"

template <typename API>
__device__ void take_turn(API* FLAMEGPU, const Store& s, unsigned int row) {
    const auto& env = FLAMEGPU->environment;
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    auto occupied = env.template getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    auto pollution = env.template getMacroProperty<float, MAX_CELLS>("pollution");
    const bool polluting = env.template getProperty<unsigned int>("pollution_active") != 0u;
    const bool combat = env.template getProperty<unsigned int>("combat") != 0u;

    // Move: to the deferred-acceptance target (Python movement.move after the choice), or with combat to the site
    // combat_move chooses, killing its occupant; then Model.move_agent.
    const unsigned int start = s.start[row];
    unsigned int target = s.target[row];
    const unsigned int rank = s.rank[row];
    if (combat) {
        const CombatChoice choice = combat_choose(FLAMEGPU, s, row);
        target = choice.site;
        touch(s, target, rank, 9);
        if (choice.victim >= 0) {
            const unsigned int victim = static_cast<unsigned int>(choice.victim);
            combat_kill(s, victim, row, env.template getProperty<double>("combat_alpha"));
            if (env.template getProperty<unsigned int>("inheritance")) pay_heirs(s, victim);
        }
    }
    touch(s, start, rank, 0);
    touch(s, target, rank, 1);
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
    // Harvest, with production pollution (p.47); combat_move harvests without it. The sites' sugar is the store's
    // during the turns (stage_sites), so a combat scan can read it while other turns harvest.
    const float harvest = s.site_sugar[target];
    s.site_sugar[target] = 0.0f;
    s.sugar[row] += static_cast<double>(harvest);
    if (polluting && !combat) pollution[target] += env.template getProperty<float>("pollution_alpha") * harvest;
    const bool with_spice = env.template getProperty<unsigned int>("spice") != 0u;
    if (with_spice) {  // and the site's spice (Python move)
        s.spice[row] += static_cast<double>(s.site_spice[target]);
        s.site_spice[target] = 0.0f;
    }
    // Metabolism, with consumption pollution from the sugar burned; death when sugar, or spice, runs out (pp.25, 97).
    const int metabolism = s.metabolism[row];
    s.sugar[row] -= static_cast<double>(metabolism);
    if (with_spice) s.spice[row] -= static_cast<double>(s.spice_metabolism[row]);
    if (polluting) pollution[target] += env.template getProperty<float>("pollution_beta") * static_cast<float>(metabolism);
    if (s.sugar[row] <= 0.0 || (with_spice && s.spice[row] <= 0.0)) {
        s.dead[row] = 1u;
        s.death_key[row] = turn_death_key(rank, false);
        s.site_row[target] = -1;
        occupied[target].exchange(0u);
        // Python Model.die: credit's on_death, then rule I (with spice, the good not run out may be left to the heirs).
        // Both find the heirs now, so they run in serial mode only (ruling R1). Without inheritance a starved agent's
        // loans go after the turns (loans.cu, rebuild_loans).
        if (env.template getProperty<unsigned int>("inheritance")) {
            if (env.template getProperty<unsigned int>("credit")) credit_on_death(s, row);
            pay_heirs(s, row);
        }
        return;
    }
    // Neighbours: the four von Neumann sites as they stand now (p.39), kept for update_friends (Python agent.neighbors).
    const int x = s.x[row], y = s.y[row];
    int met[4];
    int n = 0;
    for (int d = 0; d < 4; ++d) {
        const unsigned int site = static_cast<unsigned int>(wrap(x + MOVE_DX[d], w) + wrap(y + MOVE_DY[d], h) * w);
        touch(s, site, rank, 2);
        if (s.site_row[site] >= 0) met[n++] = s.site_row[site];
    }
    s.neighbors[row] = static_cast<unsigned int>(n);
    if (env.template getProperty<unsigned int>("sex")) mate(FLAMEGPU, s, row);
    if (env.template getProperty<unsigned int>("culture")) {
        transmit(FLAMEGPU, s, row);
        update_friends(s, row, met, n);
    }
    if (env.template getProperty<unsigned int>("trade")) trade_with_neighbors(FLAMEGPU, s, row);
    // Python's last_income: this period's sugar harvest minus its metabolism (credit's creditworthiness, p.132).
    if (env.template getProperty<unsigned int>("credit")) {
        seek_credit(FLAMEGPU, s, row, static_cast<double>(harvest) - static_cast<double>(metabolism));
    }
}

#endif  // SRC_TURN_CUH_
