// Group membership from cultural tags (p.73), shared by the host's setup and the device's rules.
#ifndef SRC_TRIBE_H_
#define SRC_TRIBE_H_

#include <bitset>
#include <cstdint>

// Python's culture.tribe: Blue when 0s outnumber 1s, Red otherwise (bit i is tag i).
__host__ __device__ inline bool is_blue(uint64_t tags, int length) {
#ifdef __CUDA_ARCH__
    return 2 * __popcll(tags) < length;
#else
    return 2 * static_cast<int>(std::bitset<64>(tags).count()) < length;
#endif
}

#endif  // SRC_TRIBE_H_
