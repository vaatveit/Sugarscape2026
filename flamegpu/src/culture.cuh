// Culture K and networks of friends in the turn, line for line with Python's sugarscape.rules.culture (pp.72-80;
// spec 2026-10-25-gpu-full-parity, section 4). Included only by model.cu (via turn.cuh).
#ifndef SRC_CULTURE_CUH_
#define SRC_CULTURE_CUH_

#include "looks.cuh"
#include "model.h"
#include "rules.cuh"
#include "store.h"

// A friend that is a newborn of this period: its uid comes after the turns, so the friend is kept as its row with this
// bit until StoreHost::birth_uids writes the uid in.
constexpr unsigned int PROVISIONAL_FRIEND = 0x80000000u;

__device__ __forceinline__ int hamming(uint64_t a, uint64_t b) { return __popcll(a ^ b); }

// The friend reference of a row: its uid, or for a newborn its row marked provisional.
__device__ __forceinline__ unsigned int friend_ref(const Store& s, int r) {
    return s.uid[r] == NO_UID ? (PROVISIONAL_FRIEND | static_cast<unsigned int>(r)) : s.uid[r];
}

// Python's f.alive at this agent's turn: the uid must name this period's row (a stale map entry names a dead agent) and
// that row must not have died in a turn earlier in the order. A newborn of this period (a provisional ref) is only
// befriended after this check in its friend's own turn, and has its uid before the next, so its branch is defensive.
__device__ __forceinline__ bool friend_alive(const Store& s, unsigned int ref) {
    if (ref & PROVISIONAL_FRIEND) return !s.dead[ref & ~PROVISIONAL_FRIEND];
    if (ref >= s.uid_capacity) return false;
    const int r = s.uid_row[ref];
    return r >= 0 && static_cast<unsigned int>(r) < s.n_rows && s.uid[r] == ref && !s.dead[r];
}

// Rule K's transmission (Python culture.transmit): each neighbour as it stands now (after mating), in random order, gets
// the agent's tag at a random position.
template <typename API>
__device__ void transmit(API* FLAMEGPU, const Store& s, unsigned int row) {
    const auto& env = FLAMEGPU->environment;
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    const int length = static_cast<int>(env.template getProperty<unsigned int>("tag_length"));
    const int a = static_cast<int>(row);
    int neighbours[4];
    int n = 0;
    for (int d = 0; d < 4; ++d) {
        const unsigned int site = static_cast<unsigned int>(wrap(s.x[a] + dir_dx(d), w) + wrap(s.y[a] + dir_dy(d), h) * w);
        touch(s, site, s.rank[a], 6);
        if (s.site_row[site] >= 0) neighbours[n++] = s.site_row[site];
    }
    for (int i = n - 1; i > 0; --i) {  // rng.permutation
        const int j = draw_between(FLAMEGPU, 0, i);
        const int t = neighbours[i];
        neighbours[i] = neighbours[j];
        neighbours[j] = t;
    }
    for (int i = 0; i < n; ++i) {
        const int other = neighbours[i];
        const int pos = draw_between(FLAMEGPU, 0, length - 1);
        const uint64_t bit = 1ull << pos;
        s.tags[other] = (s.tags[other] & ~bit) | (s.tags[a] & bit);
    }
}

// Networks of friends (Python culture.update_friends): drop dead friends, then remember the culturally nearest of the
// neighbours met (before mating), up to five, by the distance at the encounter. A newcomer displaces the stored-farthest
// (the first of equal maxima) only when strictly closer.
__device__ void update_friends(const Store& s, unsigned int row, const int* met, int n_met) {
    const int a = static_cast<int>(row);
    unsigned int* uid = s.friend_uid + row * MAX_FRIENDS;
    unsigned int* dist = s.friend_dist + row * MAX_FRIENDS;
    unsigned int k = 0;
    for (unsigned int f = 0; f < s.n_friends[a]; ++f) {
        // --check: a friend alive at the period's start is read where it stands now (touch point 12; footprint.cuh,
        // friend_sites).
        if (!(uid[f] & PROVISIONAL_FRIEND) && uid[f] < s.uid_capacity) {
            const int r = s.uid_row[uid[f]];
            if (r >= 0 && static_cast<unsigned int>(r) < s.n_rows && s.uid[r] == uid[f]) {
                touch_row(s, static_cast<unsigned int>(r), s.rank[a], 12);
            }
        }
        if (!friend_alive(s, uid[f])) continue;
        uid[k] = uid[f];
        dist[k] = dist[f];
        ++k;
    }
    for (int i = 0; i < n_met; ++i) {
        const int other = met[i];
        if (other == a || s.dead[other]) continue;
        const unsigned int ref = friend_ref(s, other);
        bool known = false;
        for (unsigned int f = 0; f < k; ++f) known = known || uid[f] == ref;
        if (known) continue;
        const unsigned int d = static_cast<unsigned int>(hamming(s.tags[a], s.tags[other]));
        if (k < MAX_FRIENDS) {
            uid[k] = ref;
            dist[k] = d;
            ++k;
            continue;
        }
        unsigned int worst = 0;
        for (unsigned int f = 1; f < k; ++f) {
            if (dist[f] > dist[worst]) worst = f;
        }
        if (d < dist[worst]) {
            uid[worst] = ref;
            dist[worst] = d;
        }
    }
    s.n_friends[a] = k;
}

#endif  // SRC_CULTURE_CUH_
