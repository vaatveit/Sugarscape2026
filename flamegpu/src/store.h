// The device store: the citizens' state during the turns, in buffers the run owns (spec 2026-10-25-gpu-full-parity,
// section 3). FLAME GPU lets no agent function write another agent's variables, and a macro property may not be read
// and written in one layer, so a turn that changes its partners works here. The scheduler (section 2) gives each turn
// sole use of everything in its footprint.
#ifndef SRC_STORE_H_
#define SRC_STORE_H_

#include <cstdint>
#include <stdexcept>
#include <vector>

#include "flamegpu/flamegpu.h"

#include "config.h"

struct SchedulerError : std::runtime_error {  // a wave ran no turn while turns were pending: exit 4
    using std::runtime_error::runtime_error;
};
struct CapacityError : std::runtime_error {  // a buffer limit was reached: exit 5
    using std::runtime_error::runtime_error;
};

// Error bits a kernel or agent function raises in Store::errors; the next host function throws CapacityError.
constexpr unsigned int STORE_UID_CAPACITY = 1u;
constexpr unsigned int NO_SITE = 0xFFFFFFFFu;  // the group after a site's last

// Device pointers. Rows are indexed by `row`, a citizen's index at publish (rows from n_rows on are newborns).
struct Store {
    unsigned int rows_capacity, cells, uid_capacity;
    // Sites.
    int* site_row;    // the row on the site now, -1 empty
    int* target_row;  // the row whose deferred-acceptance target this is, -1 none
    int* uid_row;     // uid -> row this period (check rows' uid: a stale entry names a dead agent)
    // Rows: the citizen variables a turn touches.
    int *x, *y, *vision, *metabolism, *age, *max_age, *fertility_start, *fertility_end, *disp_x, *disp_y;
    double *sugar, *initial_sugar;
    uint64_t* tags;
    unsigned int *uid, *sex, *n_children, *parent_a, *parent_b, *friend_uid, *friend_dist, *n_friends;
    unsigned int *moved, *neighbors;
    unsigned int* look_seed;      // the period's looks (start_period), for partners in sight
    uint64_t* newborn_key;        // a newborn's place in creation order: its parent's rank << 32 | mating order
    unsigned int n_rows;          // citizens this period; rows from n_rows on are newborns
    unsigned int* newborn_count;
    // Rows: the turn's own state.
    unsigned int *start, *target;  // sites
    uint64_t* key;                 // order_key: larger is earlier
    unsigned int *rank;            // position in the period's order, 0 first
    unsigned int *dead, *done, *ran;
    int* counter;                  // footprint groups still to finish before this turn may run
    unsigned int *fp_count, *fp_offset;  // the row's footprint entries, before sorting (fill order)
    // Footprint entries after sorting by (site, rank) and removing duplicates.
    int* entry_pos;               // fill-order entry -> unique entry, -1 for a duplicate
    uint64_t* unique_key;         // unique entry -> site << 32 | rank, sorted
    unsigned int* group_first;    // group id -> first unique entry; group_first[n_groups] = n_unique
    unsigned int* group_site;     // group id -> site; group_site[n_groups] = NO_SITE
    unsigned int* entry_group;    // unique entry -> group id
    unsigned int* rank_row;       // rank -> row
    // Counters (one each).
    unsigned int *errors, *ran_count, *done_count;
    // --check: every site a turn touches must be in its footprint (touch()); the first miss is kept as
    // {misses, site, rank, where}.
    unsigned int check_footprints, n_unique;
    unsigned int* footprint_miss;
};

// --check: whether (site, rank) is one of the sorted unique footprint entries; a miss is counted and the first kept.
__device__ __forceinline__ void touch(const Store& s, unsigned int site, unsigned int rank, unsigned int where) {
    if (!s.check_footprints) return;
    const uint64_t want = (static_cast<uint64_t>(site) << 32) | rank;
    unsigned int lo = 0, hi = s.n_unique;
    while (lo < hi) {
        const unsigned int mid = (lo + hi) / 2;
        if (s.unique_key[mid] < want) lo = mid + 1;
        else hi = mid;
    }
    if (lo < s.n_unique && s.unique_key[lo] == want) return;
    if (atomicAdd(&s.footprint_miss[0], 1u) == 0u) {
        s.footprint_miss[1] = site;
        s.footprint_miss[2] = rank;
        s.footprint_miss[3] = where;
    }
}

// The host side of the store: allocation, the period's scheduling, and the error check.
class StoreHost {
 public:
    // check_footprints: --check's footprint test (touch()).
    StoreHost(const RunConfig& cfg, unsigned int uid_capacity, bool check_footprints);
    ~StoreHost();
    StoreHost(const StoreHost&) = delete;
    StoreHost& operator=(const StoreHost&) = delete;

    // The Store's device address, for the environment property "store".
    uint64_t device_address() const { return reinterpret_cast<uint64_t>(d_store_); }
    // Before publish: every site empty and untargeted, the counters cleared.
    void prepare(unsigned int n_rows);
    // After publish: ranks in the period's order, footprints, groups and wait counters (section 2).
    void schedule(unsigned int n_rows, const RunConfig& cfg);
    // The turns that ran in the last wave, and all done so far; clears the wave's count.
    void wave_counts(unsigned int* ran, unsigned int* done);
    // After the turns: the newborns get uids next_uid, next_uid + 1, ... in creation order; returns how many.
    unsigned int birth_uids(unsigned int next_uid);
    // Throws CapacityError for any error bit a kernel raised.
    void check_errors();
    // --check: the first site a turn touched outside its footprint, as {misses, site, rank, where}; clears it.
    std::vector<unsigned int> footprint_misses();

 private:
    void grow_entries(size_t n);
    Store h_{};
    Store* d_store_ = nullptr;
    std::vector<void*> owned_;
    size_t entries_capacity_ = 0, temp_bytes_ = 0;
    uint64_t *entry_key_ = nullptr, *entry_key_sorted_ = nullptr;
    unsigned int *entry_write_ = nullptr, *entry_idx_ = nullptr, *entry_idx_sorted_ = nullptr;
    unsigned int *unique_write_ = nullptr, *keep_ = nullptr, *keep_scan_ = nullptr, *start_flag_ = nullptr;
    uint64_t *rank_keys_ = nullptr, *rank_keys_sorted_ = nullptr;
    unsigned int *rank_rows_ = nullptr;
    void* temp_ = nullptr;
};

// R's newcomers' uids in Python's creation order: the order of the deaths that made room for them (spec section 3).
// Each unplaced newcomer posts its death key (dying agent's: starved ones by their place in the period's order, then
// old age by uid, bit 63 set) and takes the uid its key's position gives it.
struct NewcomerSlots {
    uint64_t* key;
    unsigned int* slot;  // posting order
    unsigned int* uid;   // by posting order
    unsigned int* count;
};

class NewcomerUids {
 public:
    explicit NewcomerUids(unsigned int cells);
    ~NewcomerUids();
    NewcomerUids(const NewcomerUids&) = delete;
    NewcomerUids& operator=(const NewcomerUids&) = delete;
    uint64_t device_address() const { return reinterpret_cast<uint64_t>(d_slots_); }
    // Gives the posted newcomers uids next_uid, next_uid + 1, ... in death-key order; returns how many.
    unsigned int assign(unsigned int next_uid);

 private:
    NewcomerSlots h_{}, *d_slots_ = nullptr;
    uint64_t* sorted_key_ = nullptr;
    unsigned int* sorted_slot_ = nullptr;
    void* temp_ = nullptr;
    size_t temp_bytes_ = 0;
};

// Rule I at old age (spec section 4): the period's dying post (uid, sugar); sorted by uid, each heir finds its parents
// by binary search, counts itself, then takes its shares.
struct Dying {
    unsigned int* uid;    // posted, then sorted
    double* sugar;        // posted, then sorted with the uids
    unsigned int* heirs;  // living, non-dying children per sorted entry
    unsigned int* count;  // posted entries
    unsigned int n;       // sorted entries (after DyingTable::sort)
};

// The sorted entry of a dying uid, or -1.
__device__ __forceinline__ int find_dying(const Dying& d, unsigned int uid) {
    unsigned int lo = 0, hi = d.n;
    while (lo < hi) {
        const unsigned int mid = (lo + hi) / 2;
        if (d.uid[mid] < uid) lo = mid + 1;
        else hi = mid;
    }
    return lo < d.n && d.uid[lo] == uid ? static_cast<int>(lo) : -1;
}

class DyingTable {
 public:
    explicit DyingTable(unsigned int cells);
    ~DyingTable();
    DyingTable(const DyingTable&) = delete;
    DyingTable& operator=(const DyingTable&) = delete;
    uint64_t device_address() const { return reinterpret_cast<uint64_t>(d_); }
    // Before the dying post: the device table names the posting arrays.
    void posting();
    // After the dying have posted: sort by uid, clear the heir counts, and reset the posting count.
    void sort();

 private:
    Dying h_{}, *d_ = nullptr;
    unsigned int *posted_uid_ = nullptr, *order_ = nullptr, *sorted_order_ = nullptr;
    double* posted_sugar_ = nullptr;
    void* temp_ = nullptr;
    size_t temp_bytes_ = 0;
};

// The death key of a citizen that starves (rank: its place in the period's order) or dies of old age (its uid).
__host__ __device__ inline uint64_t starved_key(uint64_t rank) { return rank; }
__host__ __device__ inline uint64_t old_age_key(unsigned int uid) { return (1ull << 63) | uid; }

#endif  // SRC_STORE_H_
