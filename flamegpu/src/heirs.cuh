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

// The living children of row, in Python's children order (birth order: by uid, then this period's newborns in creation
// order), as loan references: the uid, or for a newborn its row marked PROVISIONAL_PARENT until StoreHost::birth_uids.
// More than MAX_HEIRS raises STORE_HEIR_CAPACITY (exit 5). Returns how many.
__device__ __forceinline__ unsigned int heirs_in_order(const Store& s, unsigned int row, unsigned int* out) {
    uint64_t keys[MAX_HEIRS];
    unsigned int rows[MAX_HEIRS];
    unsigned int n = 0;
    const unsigned int total = s.n_rows + *s.newborn_count;
    for (unsigned int r = 0; r < total; ++r) {
        if (r == row || s.dead[r] || !is_child_of(s, r, row)) continue;
        if (n == MAX_HEIRS) {
            atomicOr(s.errors, STORE_HEIR_CAPACITY);
            break;
        }
        // uids sort before newborns (bit 63), newborns by their place in creation order (newborn_key's 63 bits).
        keys[n] = s.uid[r] != NO_UID ? s.uid[r] : ((1ull << 63) | (s.newborn_key[r] & ~(1ull << 63)));
        rows[n++] = r;
    }
    for (unsigned int i = 1; i < n; ++i) {  // insertion sort: a handful of children
        for (unsigned int j = i; j > 0 && keys[j - 1] > keys[j]; --j) {
            const uint64_t k = keys[j];
            keys[j] = keys[j - 1];
            keys[j - 1] = k;
            const unsigned int r = rows[j];
            rows[j] = rows[j - 1];
            rows[j - 1] = r;
        }
    }
    for (unsigned int i = 0; i < n; ++i) out[i] = s.uid[rows[i]] != NO_UID ? s.uid[rows[i]] : (PROVISIONAL_PARENT | rows[i]);
    return n;
}

#endif  // SRC_HEIRS_CUH_
