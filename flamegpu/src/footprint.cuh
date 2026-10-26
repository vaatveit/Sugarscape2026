// A turn's footprint: the sites it may read and the sites it may write, fixed for the period from the state at the
// start of the turns (spec 2026-10-25-gpu-full-parity, section 2). Included by store.cu (the scheduler) only.
#ifndef SRC_FOOTPRINT_CUH_
#define SRC_FOOTPRINT_CUH_

#include "store.h"

struct FootprintEnv {
    int width, height;
};

__device__ __forceinline__ int fp_wrap(int v, int n) { return ((v % n) + n) % n; }

__device__ __forceinline__ unsigned int fp_site(int x, int y, const FootprintEnv& e) {
    return static_cast<unsigned int>(fp_wrap(x, e.width) + fp_wrap(y, e.height) * e.width);
}

// Calls emit(site, write) for every site of the row's turn; a site may come more than once (the scheduler removes
// duplicates, write winning). Chapter II's rules: the move writes the start and the target; metabolism and the
// neighbour count read and write the four sites around the target (the neighbour rules of later tasks write there).
template <typename Emit>
__device__ void footprint(const Store& s, unsigned int row, const FootprintEnv& e, Emit emit) {
    const unsigned int start = s.start[row], target = s.target[row];
    emit(start, true);
    emit(target, true);
    const int tx = static_cast<int>(target % static_cast<unsigned int>(e.width));
    const int ty = static_cast<int>(target / static_cast<unsigned int>(e.width));
    emit(fp_site(tx + 1, ty, e), true);
    emit(fp_site(tx - 1, ty, e), true);
    emit(fp_site(tx, ty + 1, e), true);
    emit(fp_site(tx, ty - 1, e), true);
}

#endif  // SRC_FOOTPRINT_CUH_
