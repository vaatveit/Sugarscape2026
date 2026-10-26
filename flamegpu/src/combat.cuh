// Combat C_alpha in the turn, line for line with Python's sugarscape.rules.combat (pp.82-83, App. B pp.183-184; spec
// 2026-10-25-gpu-full-parity, sections 2 and 4). It replaces movement M: the turn scans, checks for retaliation,
// attacks, moves and harvests. Included only by model.cu (via turn.cuh).
#ifndef SRC_COMBAT_CUH_
#define SRC_COMBAT_CUH_

#include "looks.cuh"
#include "model.h"
#include "rules.cuh"
#include "sex.cuh"
#include "store.h"
#include "tribe.h"

struct CombatChoice {
    unsigned int site;
    int victim;  // the row on the site, -1 when it is empty
};

// Python vulnerable: along any of the four lines from the candidate site, out to the attacker's vision, an occupant
// other than the attacker and the candidate's victim, of another tribe, that would be bigger than the attacker after
// taking the site. The looks are the candidate's own (retaliation_distance).
__device__ __forceinline__ bool vulnerable(const Store& s, int a, int x, int y, double reward, int victim,
                                           unsigned int cand, int w, int h, int stride, int tag_length) {
    const double after = s.sugar[a] + reward;
    const bool blue = is_blue(s.tags[a], tag_length);
    const int looks = s.vision[a] / stride;
    for (int d = 0; d < 4; ++d) {
        for (int k = 0; k < looks; ++k) {
            const int dist = retaliation_distance(s.look_seed[a], cand, d, k, stride);
            const unsigned int site = static_cast<unsigned int>(wrap(x + dir_dx(d) * dist, w) + wrap(y + dir_dy(d) * dist, h) * w);
            touch(s, site, s.rank[a], 8);
            const int other = s.site_row[site];
            if (other >= 0 && other != a && other != victim && is_blue(s.tags[other], tag_length) != blue &&
                s.sugar[other] > after) {
                return true;
            }
        }
    }
    return false;
}

// Python combat_candidates, vulnerable and the choice in combat_move: the own site first, then each direction in the
// period's order out to vision; an occupied site is a candidate only when its occupant is of another tribe and no
// richer (sight continues past it either way). The nearest safe site of greatest reward wins, the first on ties; with
// no safe site, the own site.
template <typename API>
__device__ CombatChoice combat_choose(API* FLAMEGPU, const Store& s, unsigned int row) {
    const auto& env = FLAMEGPU->environment;
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    const int stride = static_cast<int>(env.template getProperty<unsigned int>("look_stride"));
    const int tag_length = static_cast<int>(env.template getProperty<unsigned int>("tag_length"));
    const double alpha = env.template getProperty<double>("combat_alpha");
    const int a = static_cast<int>(row);
    const int x = s.x[a], y = s.y[a];
    const bool blue = is_blue(s.tags[a], tag_length);
    const int looks = s.vision[a] / stride;

    const unsigned int own = static_cast<unsigned int>(x + y * w);
    CombatChoice best{own, -1};
    double best_reward = 0.0;
    int best_dist = 0;
    bool safe_found = false;
    const double own_reward = static_cast<double>(s.site_sugar[own]);
    if (!vulnerable(s, a, x, y, own_reward, -1, 0u, w, h, stride, tag_length)) {
        safe_found = true;
        best_reward = own_reward;
    }
    const unsigned int dir_order = s.dir_order[a];
    for (int i = 0; i < 4; ++i) {
        const int d = static_cast<int>((dir_order >> (2 * i)) & 3u);
        for (int k = 0; k < looks; ++k) {
            if (repeated_look(s.look_seed[a], d, k, stride)) continue;  // each site is one candidate, checked once
            const int dist = stride == 1 ? k + 1 : look_distance(s.look_seed[a], d, k, stride);
            const int cx = wrap(x + dir_dx(d) * dist, w), cy = wrap(y + dir_dy(d) * dist, h);
            const unsigned int site = static_cast<unsigned int>(cx + cy * w);
            touch(s, site, s.rank[a], 7);
            const int occupant = s.site_row[site];
            double reward = static_cast<double>(s.site_sugar[site]);
            if (occupant >= 0) {
                if (is_blue(s.tags[occupant], tag_length) == blue || s.sugar[occupant] > s.sugar[a]) continue;
                reward += fmin(alpha, s.sugar[occupant]);
            }
            if (vulnerable(s, a, cx, cy, reward, occupant, combat_candidate_id(d, k, looks), w, h, stride, tag_length)) {
                continue;
            }
            if (!safe_found || reward > best_reward || (reward == best_reward && dist < best_dist)) {
                safe_found = true;
                best = {site, occupant};
                best_reward = reward;
                best_dist = dist;
            }
        }
    }
    return best;
}

// The victim loses min(alpha, its sugar) to the attacker and dies in the attacker's turn, before the attacker moves onto
// its site (Python combat_move, then Model.die). It takes no turn of its own (run_turns).
__device__ __forceinline__ void combat_kill(const Store& s, unsigned int victim, unsigned int attacker, double alpha) {
    const double take = fmin(alpha, s.sugar[victim]);
    s.sugar[victim] -= take;
    s.sugar[attacker] += take;
    s.dead[victim] = 1u;
    s.death_key[victim] = turn_death_key(s.rank[attacker], true);
}

// Whether row c names row p as a parent: by uid, or for a parent born this period by its row (sex.cuh,
// PROVISIONAL_PARENT, until StoreHost::birth_uids).
__device__ __forceinline__ bool is_child_of(const Store& s, unsigned int c, unsigned int p) {
    const unsigned int ref = s.uid[p] == NO_UID ? (PROVISIONAL_PARENT | p) : s.uid[p];
    return s.parent_a[c] == ref || s.parent_b[c] == ref;
}

// Rule I for a combat victim (Python Model.die): what it keeps after the take, when positive, goes in equal shares to
// its living children, wherever they are. They are found only now, so combat with inheritance runs one turn per wave
// (spec section 2; RunConfig::serial) and this one thread may scan every row, this period's newborns included.
__device__ __forceinline__ void pay_victim_heirs(const Store& s, unsigned int victim) {
    if (!(s.sugar[victim] > 0.0)) return;
    const unsigned int rows = s.n_rows + *s.newborn_count;
    unsigned int heirs = 0;
    for (unsigned int r = 0; r < rows; ++r) heirs += (r != victim && !s.dead[r] && is_child_of(s, r, victim)) ? 1u : 0u;
    if (heirs == 0) return;
    const double share = s.sugar[victim] / static_cast<double>(heirs);
    for (unsigned int r = 0; r < rows; ++r) {
        if (r != victim && !s.dead[r] && is_child_of(s, r, victim)) s.sugar[r] += share;
    }
}

#endif  // SRC_COMBAT_CUH_
