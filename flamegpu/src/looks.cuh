// The strided looks along a lattice line (xl design, section 2a): pure functions of a period's look seed, shared by
// movement, the scheduler's footprints and rule S's partners in sight.
#ifndef SRC_LOOKS_CUH_
#define SRC_LOOKS_CUH_

// A 32-bit integer hash (lowbias32: Wellons, "Prospecting for Hash Functions").
__host__ __device__ __forceinline__ unsigned int mix32(unsigned int h) {
    h ^= h >> 16;
    h *= 0x7FEB352Du;
    h ^= h >> 15;
    h *= 0x846CA68Bu;
    h ^= h >> 16;
    return h;
}

// With look stride s > 1, the distance looked at in direction d (VON_NEUMANN index) and stretch k: s·k plus an offset
// uniform on 1..s (Python look_distances). A pure function of the period's look seed, so every movement round of a
// period sees the same sites (xl design, section 2a).
__host__ __device__ __forceinline__ int look_distance(unsigned int look_seed, int d, int k, int stride) {
    const unsigned int h = mix32(mix32(look_seed ^ (static_cast<unsigned int>(d) * 0x9E3779B9u)) ^
                                 (static_cast<unsigned int>(k + 1) * 0x85EBCA6Bu));
    return stride * k + 1 + static_cast<int>(h % static_cast<unsigned int>(stride));
}

// Rule S's partners in sight look with the period's look seed salted, so they are drawn apart from movement's looks
// (spec 2026-10-25-gpu-full-parity, Part A Task 5).
constexpr unsigned int SIGHT_SALT = 0x5EED5EEDu;

// The distance of rule S's k-th look along direction d (1..vision at stride 1).
__host__ __device__ __forceinline__ int sight_distance(unsigned int look_seed, int d, int k, int stride) {
    return stride == 1 ? k + 1 : look_distance(look_seed ^ SIGHT_SALT, d, k, stride);
}

// Directions in the Python project's VON_NEUMANN order: east, west, north, south.
__host__ __device__ __forceinline__ int dir_dx(int d) { return d == 0 ? 1 : d == 1 ? -1 : 0; }
__host__ __device__ __forceinline__ int dir_dy(int d) { return d == 2 ? 1 : d == 3 ? -1 : 0; }

#endif  // SRC_LOOKS_CUH_
