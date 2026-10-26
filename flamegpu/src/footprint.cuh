// A turn's footprint: the sites it may read and the sites it may write, fixed for the period from the state at the
// start of the turns (spec 2026-10-25-gpu-full-parity, section 2). Included by store.cu (the scheduler) only.
#ifndef SRC_FOOTPRINT_CUH_
#define SRC_FOOTPRINT_CUH_

#include "looks.cuh"
#include "store.h"

struct FootprintEnv {
    int width, height, stride;
    bool sex, mate_vision;  // rule S on; partners in sight (mate_contact = "vision") rather than the four neighbours
    bool culture;           // rule K and friends
};

__device__ __forceinline__ int fp_wrap(int v, int n) { return ((v % n) + n) % n; }

__device__ __forceinline__ unsigned int fp_site(int x, int y, const FootprintEnv& e) {
    return static_cast<unsigned int>(fp_wrap(x, e.width) + fp_wrap(y, e.height) * e.width);
}

template <typename Emit>
__device__ __forceinline__ void around(int x, int y, const FootprintEnv& e, Emit& emit) {
    for (int d = 0; d < 4; ++d) emit(fp_site(x + dir_dx(d), y + dir_dy(d), e), true);
}

// Calls emit(site, write) for every site of the row's turn; a site may come more than once (the scheduler removes
// duplicates, write winning).
// - Chapter II's rules: the move writes the start and the target; metabolism and the neighbour count read and write
//   the four sites around the target (the neighbour rules write there).
// - Rule S, for an agent of childbearing age (fixed for the period): with the four neighbours as partners, every site
//   within distance 2 of the target (partners, and a child next to either parent); with partners in sight, every
//   sight-line site from the target and the four sites around each (spec section 2).
template <typename Emit>
__device__ void footprint(const Store& s, unsigned int row, const FootprintEnv& e, Emit emit) {
    const unsigned int start = s.start[row], target = s.target[row];
    emit(start, true);
    emit(target, true);
    const int tx = static_cast<int>(target % static_cast<unsigned int>(e.width));
    const int ty = static_cast<int>(target / static_cast<unsigned int>(e.width));
    around(tx, ty, e, emit);
    // Friends anywhere in the world (K reads whether each is alive): read where the friend stands at this turn, its
    // start if it comes later in the order, else its target; the friend's own turn writes both (spec section 2).
    if (e.culture) {
        for (unsigned int f = 0; f < s.n_friends[row]; ++f) {
            const unsigned int uid = s.friend_uid[row * MAX_FRIENDS + f];
            if (uid >= s.uid_capacity) continue;
            const int r = s.uid_row[uid];
            if (r < 0 || static_cast<unsigned int>(r) >= s.n_rows || s.uid[r] != uid) continue;  // died before
            emit(s.key[r] < s.key[row] ? s.start[r] : s.target[r], false);
        }
    }
    const bool childbearing = e.sex && s.sex[row] != 0u && s.fertility_start[row] <= s.age[row] &&
                              s.age[row] < s.fertility_end[row];
    if (!childbearing) return;
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

#endif  // SRC_FOOTPRINT_CUH_
