// A turn's footprint: the sites it may read and the sites it may write, fixed for the period from the state at the
// start of the turns (spec 2026-10-25-gpu-full-parity, section 2). Included by store.cu (the scheduler) only. The
// --check touch points that test it: 0-2 the move and neighbours, 3-4 and 6 rules S and K, 7-9 combat, 10 T, 11 L's
// neighbours, 12 friends' rows and 13 lenders' rows (touch_row), 14 E's neighbours (disease.cuh). E's partners are the
// four sites around the target, which every footprint already writes.
#ifndef SRC_FOOTPRINT_CUH_
#define SRC_FOOTPRINT_CUH_

#include "looks.cuh"
#include "store.h"

struct FootprintEnv {
    int width, height, stride;
    bool sex, mate_vision;  // rule S on; partners in sight (mate_contact = "vision") rather than the four neighbours
    bool culture;           // rule K and friends
    bool combat;            // combat C_alpha: the whole turn, movement included, from the start site
    bool credit;            // rule L: the lenders of the row's start-of-period loans, wherever they are
};

__device__ __forceinline__ int fp_wrap(int v, int n) { return ((v % n) + n) % n; }

__device__ __forceinline__ unsigned int fp_site(int x, int y, const FootprintEnv& e) {
    return static_cast<unsigned int>(fp_wrap(x, e.width) + fp_wrap(y, e.height) * e.width);
}

template <typename Emit>
__device__ __forceinline__ void around(int x, int y, const FootprintEnv& e, Emit& emit) {
    for (int d = 0; d < 4; ++d) emit(fp_site(x + dir_dx(d), y + dir_dy(d), e), true);
}

// footprint() (below) calls emit(site, write) for every site of the row's turn; a site may come more than once (the
// scheduler removes duplicates, write winning).
// - Chapter II's rules: the move writes the start and the target; metabolism and the neighbour count read and write
//   the four sites around the target (the neighbour rules write there).
// - Rule S, for an agent of childbearing age (fixed for the period): with the four neighbours as partners, every site
//   within distance 2 of the target (partners, and a child next to either parent); with partners in sight, every
//   sight-line site from the target and the four sites around each (spec section 2).
// - Combat: the same around every site the turn may end on (combat_candidate), in place of a fixed target.

// Combat's candidate site P with id cand (combat.cuh): the turn may move to P or kill there, then metabolise there and
// meet, mate and transmit around it (writes P and the four sites around it); it reads P's retaliation lines.
template <typename Emit>
__device__ void combat_candidate(const Store& s, unsigned int row, int px, int py, unsigned int cand,
                                 const FootprintEnv& e, Emit& emit) {
    emit(fp_site(px, py, e), true);
    around(px, py, e, emit);
    const int looks = s.vision[row] / e.stride;
    for (int d = 0; d < 4; ++d) {
        for (int k = 0; k < looks; ++k) {
            const int dist = retaliation_distance(s.look_seed[row], cand, d, k, e.stride);
            emit(fp_site(px + dir_dx(d) * dist, py + dir_dy(d) * dist, e), false);
        }
    }
}

// Calls f(px, py, cand) for every combat candidate site of the row's scan: the start (cand 0), then every sight-line
// site whether or not it turns out to be a candidate.
template <typename F>
__device__ void for_each_combat_site(const Store& s, unsigned int row, const FootprintEnv& e, F f) {
    const int sx = static_cast<int>(s.start[row] % static_cast<unsigned int>(e.width));
    const int sy = static_cast<int>(s.start[row] / static_cast<unsigned int>(e.width));
    f(sx, sy, 0u);
    const int looks = s.vision[row] / e.stride;
    for (int d = 0; d < 4; ++d) {
        for (int k = 0; k < looks; ++k) {
            const int dist = e.stride == 1 ? k + 1 : look_distance(s.look_seed[row], d, k, e.stride);
            f(sx + dir_dx(d) * dist, sy + dir_dy(d) * dist, combat_candidate_id(d, k, looks));
        }
    }
}

// Rule S from (tx, ty), for an agent of childbearing age (fixed for the period), beyond the four sites around it: with
// the four neighbours as partners, the sites at distance 2 (a child next to a partner); with partners in sight, every
// sight-line site and the four sites around each (spec section 2).
template <typename Emit>
__device__ void sex_sites(const Store& s, unsigned int row, int tx, int ty, const FootprintEnv& e, Emit& emit) {
    if (!e.mate_vision) {
        for (int i = -2; i <= 2; ++i) {
            for (int j = -2; j <= 2; ++j) {
                if (abs(i) + abs(j) == 2) emit(fp_site(tx + i, ty + j, e), true);
            }
        }
        return;
    }
    const int looks = s.vision[row] / e.stride;
    for (int k = 0; k < looks; ++k) {
        for (int d = 0; d < 4; ++d) {
            const int dist = sight_distance(s.look_seed[row], d, k, e.stride);
            const int px = tx + dir_dx(d) * dist, py = ty + dir_dy(d) * dist;
            emit(fp_site(px, py, e), true);
            around(px, py, e, emit);
        }
    }
}

// Friends anywhere in the world (K reads whether each is alive): read where the friend stands at this turn, alive or
// killed there. A friend later in the order is still at its start. One earlier in the order is at its target, or with
// combat at its start or any site of its scan; the friend's own turn writes all of those (spec section 2).
template <typename Emit>
__device__ void friend_sites(const Store& s, unsigned int row, const FootprintEnv& e, Emit& emit) {
    for (unsigned int f = 0; f < s.n_friends[row]; ++f) {
        const unsigned int uid = s.friend_uid[row * MAX_FRIENDS + f];
        if (uid >= s.uid_capacity) continue;
        const int r = s.uid_row[uid];
        if (r < 0 || static_cast<unsigned int>(r) >= s.n_rows || s.uid[r] != uid) continue;  // died before
        if (s.key[r] < s.key[row]) {
            emit(s.start[r], false);
        } else if (e.combat) {
            for_each_combat_site(s, static_cast<unsigned int>(r), e,
                                 [&](int px, int py, unsigned int) { emit(fp_site(px, py, e), false); });
        } else {
            emit(s.target[r], false);
        }
    }
}

// Rule L (credit.cuh): a borrower reads whether each lender of its start-of-period loans still lives, where that lender
// stands at its turn: at its start if later in the order, else at its target, as friends are read (plan
// 2026-10-26-gpu-parity-part-c, ruling R2). Credit has no combat (Python Config).
template <typename Emit>
__device__ void lender_sites(const Store& s, unsigned int row, Emit& emit) {
    const unsigned int first = s.loan_first[row], end = first + s.loan_count[row];
    for (unsigned int k = first; k < end; ++k) {
        const int r = s.book.lender_row[s.loan_entry[k]];
        if (r < 0) continue;
        emit(s.key[r] < s.key[row] ? s.start[r] : s.target[r], false);
    }
}

template <typename Emit>
__device__ void footprint(const Store& s, unsigned int row, const FootprintEnv& e, Emit emit) {
    const bool childbearing = e.sex && s.sex[row] != 0u && s.fertility_start[row] <= s.age[row] &&
                              s.age[row] < s.fertility_end[row];
    if (e.culture) friend_sites(s, row, e, emit);
    if (e.credit) lender_sites(s, row, emit);
    // Combat: the whole turn from the start site (spec section 2): writes the start, every site on its sight lines (a
    // target or a victim) and the four sites around each, with rule S's sites around each; reads the retaliation
    // lines from each of them.
    if (e.combat) {
        for_each_combat_site(s, row, e, [&](int px, int py, unsigned int cand) {
            combat_candidate(s, row, px, py, cand, e, emit);
            if (childbearing) sex_sites(s, row, px, py, e, emit);
        });
        return;
    }
    const unsigned int start = s.start[row], target = s.target[row];
    emit(start, true);
    emit(target, true);
    const int tx = static_cast<int>(target % static_cast<unsigned int>(e.width));
    const int ty = static_cast<int>(target / static_cast<unsigned int>(e.width));
    around(tx, ty, e, emit);
    if (childbearing) sex_sites(s, row, tx, ty, e, emit);
}

#endif  // SRC_FOOTPRINT_CUH_
