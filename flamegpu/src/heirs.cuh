// Rule I in the turn (Python Model.die with inheritance on): a row's living children, found by scanning every row. The
// heirs of a death in the turn can't be bounded in a footprint, so these run only in serial mode (RunConfig::serial;
// plan 2026-10-26-gpu-parity-part-c, ruling R1). Included only by model.cu (via turn.cuh).
#ifndef SRC_HEIRS_CUH_
#define SRC_HEIRS_CUH_

#include "sex.cuh"
#include "store.h"

// Whether row c names row p as a parent: by uid, or for a parent born this period by its row (sex.cuh,
// PROVISIONAL_PARENT, until StoreHost::birth_uids).
__device__ __forceinline__ bool is_child_of(const Store& s, unsigned int c, unsigned int p) {
    const unsigned int ref = s.uid[p] == NO_UID ? (PROVISIONAL_PARENT | p) : s.uid[p];
    return s.parent_a[c] == ref || s.parent_b[c] == ref;
}

// Python Model.die's shares: what the dying row holds, when positive, goes in equal shares to its living children,
// wherever they are, this period's newborns included; sugar and spice each on its own.
__device__ __forceinline__ void pay_heirs(const Store& s, unsigned int row) {
    const bool sugar = s.sugar[row] > 0.0, spice = s.spice[row] > 0.0;
    if (!sugar && !spice) return;
    const unsigned int rows = s.n_rows + *s.newborn_count;
    unsigned int heirs = 0;
    for (unsigned int r = 0; r < rows; ++r) heirs += (r != row && !s.dead[r] && is_child_of(s, r, row)) ? 1u : 0u;
    if (heirs == 0) return;
    const double sugar_share = s.sugar[row] / static_cast<double>(heirs);
    const double spice_share = s.spice[row] / static_cast<double>(heirs);
    for (unsigned int r = 0; r < rows; ++r) {
        if (r == row || s.dead[r] || !is_child_of(s, r, row)) continue;
        if (sugar) s.sugar[r] += sugar_share;
        if (spice) s.spice[r] += spice_share;
    }
}

#endif  // SRC_HEIRS_CUH_
