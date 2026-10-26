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

// Combat's retaliation scans (Python vulnerable) draw their looks afresh for each candidate site, as Python calls
// look_distances once per scan: one hash per scan, salted apart from movement's and rule S's looks.
constexpr unsigned int RETALIATION_SALT = 0xC0DEC0DEu;

// A combat candidate's place in the full scan: 0 for the agent's own site, then 1 + d * looks + k for the k-th look in
// direction d (whether or not the site turns out to be a candidate, so the footprint can name it in advance).
__host__ __device__ __forceinline__ unsigned int combat_candidate_id(int d, int k, int looks) {
    return 1u + static_cast<unsigned int>(d * looks + k);
}

// The distance of the k-th look in direction d of candidate cand's retaliation scan (1..vision at stride 1).
__host__ __device__ __forceinline__ int retaliation_distance(unsigned int look_seed, unsigned int cand, int d, int k,
                                                            int stride) {
    return stride == 1 ? k + 1
                       : look_distance(mix32(look_seed ^ RETALIATION_SALT ^ ((cand + 1u) * 0x9E3779B9u)), d, k, stride);
}

// Directions in the Python project's VON_NEUMANN order: east, west, north, south.
__host__ __device__ __forceinline__ int dir_dx(int d) { return d == 0 ? 1 : d == 1 ? -1 : 0; }
__host__ __device__ __forceinline__ int dir_dy(int d) { return d == 2 ? 1 : d == 3 ? -1 : 0; }

#endif  // SRC_LOOKS_CUH_
