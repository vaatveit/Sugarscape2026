// Immune systems and diseases as bit strings, line for line with Python's sugarscape.rules.disease (Chapter V,
// pp.141-147): bit i is the Python list's element i. Host and device: the founders' infections are on the host
// (host_state.cu), rule E in the turn (plan 2026-10-27-gpu-parity-part-d, Task 3).
#ifndef SRC_DISEASE_H_
#define SRC_DISEASE_H_

#include <cstdint>

#ifdef __CUDACC__
#define DISEASE_FN __host__ __device__ inline
#else
#define DISEASE_FN inline
#endif

// The lowest `len` bits (len < 64: a disease is shorter than an immune system of at most 64 bits).
DISEASE_FN uint64_t low_bits(int len) { return (1ull << len) - 1ull; }

DISEASE_FN int bit_count(uint64_t v) {
#ifdef __CUDA_ARCH__
    return __popcll(v);
#else
    int n = 0;
    for (; v; v &= v - 1) ++n;
    return n;
#endif
}

struct Nearest {
    int start, distance;
};

// Python's nearest_substring: the window of the immune system closest to the disease in Hamming distance; ties go to
// the leftmost window (p.142 fn 11), and the search stops at distance 0.
DISEASE_FN Nearest nearest_substring(uint64_t immune, int immune_length, uint64_t bits, int len) {
    Nearest best{0, len + 1};
    for (int start = 0; start + len <= immune_length; ++start) {
        const int d = bit_count(((immune >> start) & low_bits(len)) ^ bits);
        if (d < best.distance) {
            best = {start, d};
            if (d == 0) break;
        }
    }
    return best;
}

// Immune iff the disease is a substring of the immune system (p.142).
DISEASE_FN bool is_immune(uint64_t immune, int immune_length, uint64_t bits, int len) {
    return nearest_substring(immune, immune_length, bits, len).distance == 0;
}

// One period of learning (p.144): flip the first bit at which the nearest window differs from the disease. Returns
// whether the disease now matches.
DISEASE_FN bool immune_step(uint64_t& immune, int immune_length, uint64_t bits, int len) {
    const Nearest n = nearest_substring(immune, immune_length, bits, len);
    if (n.distance == 0) return true;
    const uint64_t diff = ((immune >> n.start) & low_bits(len)) ^ bits;
    const uint64_t lowest = diff & (~diff + 1ull);  // the first differing bit of the window
    immune ^= lowest << n.start;
    return n.distance == 1;
}

#undef DISEASE_FN

#endif  // SRC_DISEASE_H_
