#include "store.h"

#include <cub/cub.cuh>

#include <algorithm>
#include <string>
#include <tuple>

#include "footprint.cuh"

namespace {

void check(cudaError_t e, const char* what) {
    if (e != cudaSuccess) throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(e));
}

constexpr unsigned int BLOCK = 256;
unsigned int blocks(size_t n) { return static_cast<unsigned int>((n + BLOCK - 1) / BLOCK); }

int bits_for(unsigned int n) {
    int b = 1;
    while (b < 32 && (1ull << b) < n) ++b;
    return b;
}

__global__ void k_rank_keys(unsigned int n, const uint64_t* key, uint64_t* rank_keys, unsigned int* rows) {
    const unsigned int r = blockIdx.x * blockDim.x + threadIdx.x;
    if (r >= n) return;
    rank_keys[r] = ~key[r];  // ascending ~key is descending key: earliest first
    rows[r] = r;
}

__global__ void k_ranks(unsigned int n, const unsigned int* sorted_rows, Store s) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    s.rank_row[i] = sorted_rows[i];
    s.rank[sorted_rows[i]] = i;
}

__global__ void k_fp_count(unsigned int n, Store s, FootprintEnv e) {
    const unsigned int r = blockIdx.x * blockDim.x + threadIdx.x;
    if (r >= n) return;
    unsigned int k = 0;
    footprint(s, r, e, [&](unsigned int, bool) { ++k; });
    s.fp_count[r] = k;
}

__global__ void k_fp_fill(unsigned int n, Store s, FootprintEnv e, uint64_t* key, unsigned int* write, unsigned int* idx) {
    const unsigned int r = blockIdx.x * blockDim.x + threadIdx.x;
    if (r >= n) return;
    unsigned int at = s.fp_offset[r];
    const uint64_t rank = s.rank[r];
    footprint(s, r, e, [&](unsigned int site, bool w) {
        key[at] = (static_cast<uint64_t>(site) << 32) | rank;
        write[at] = w ? 1u : 0u;
        idx[at] = at;
        ++at;
    });
}

__global__ void k_gather(unsigned int n, const unsigned int* idx, const unsigned int* in, unsigned int* out) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) out[i] = in[idx[i]];
}

// The first of each run of equal (site, rank) keys stays; the run's write flags are or-ed into it.
__global__ void k_keep(unsigned int n, const uint64_t* key, unsigned int* keep) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    keep[i] = (i == 0 || key[i] != key[i - 1]) ? 1u : 0u;
}

__global__ void k_compact(unsigned int n, const uint64_t* key, const unsigned int* idx, const unsigned int* write,
                          const unsigned int* keep, const unsigned int* keep_scan, Store s, unsigned int* unique_write) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (!keep[i]) {
        s.entry_pos[idx[i]] = -1;
        return;
    }
    const unsigned int u = keep_scan[i];
    unsigned int w = 0;
    for (unsigned int j = i; j < n && key[j] == key[i]; ++j) w |= write[j];
    s.unique_key[u] = key[i];
    unique_write[u] = w;
    s.entry_pos[idx[i]] = static_cast<int>(u);
}

// A group is a maximal run of readers at a site, or a single writer.
__global__ void k_group_starts(unsigned int n, const uint64_t* key, const unsigned int* write, unsigned int* start) {
    const unsigned int u = blockIdx.x * blockDim.x + threadIdx.x;
    if (u >= n) return;
    start[u] = (u == 0 || (key[u] >> 32) != (key[u - 1] >> 32) || write[u] || write[u - 1]) ? 1u : 0u;
}

__global__ void k_groups(unsigned int n, const unsigned int* start, Store s) {
    const unsigned int u = blockIdx.x * blockDim.x + threadIdx.x;
    if (u >= n) return;
    const unsigned int g = s.entry_group[u] - 1u;  // the inclusive sum of starts counts from 1
    s.entry_group[u] = g;
    if (start[u]) {
        s.group_first[g] = u;
        s.group_site[g] = static_cast<unsigned int>(s.unique_key[u] >> 32);
    }
    if (u == n - 1) {
        s.group_first[g + 1] = n;
        s.group_site[g + 1] = NO_SITE;
    }
}

// A turn waits for every member of the group before each of its entries at the same site.
__global__ void k_counters(unsigned int n, Store s) {
    const unsigned int u = blockIdx.x * blockDim.x + threadIdx.x;
    if (u >= n) return;
    const unsigned int g = s.entry_group[u];
    const unsigned int site = static_cast<unsigned int>(s.unique_key[u] >> 32);
    if (g == 0 || s.group_site[g - 1] != site) return;
    const unsigned int row = s.rank_row[static_cast<unsigned int>(s.unique_key[u])];
    atomicAdd(&s.counter[row], static_cast<int>(s.group_first[g] - s.group_first[g - 1]));
}

}  // namespace

StoreHost::StoreHost(const RunConfig& cfg, unsigned int uid_capacity, bool check_footprints) {
    const unsigned int cells = static_cast<unsigned int>(cfg.cells());
    h_.check_footprints = check_footprints ? 1u : 0u;
    // Rows: the period's citizens (at most one per site) and its newborns, each born on a site free at that moment. A
    // dead citizen keeps its row while a child takes its site, and with combat a killed newborn keeps its row while its
    // site goes to the attacker, so rows can exceed cells. 2 x cells covers every case seen; beyond it a newborn finds
    // no row and the run stops with STORE_ROW_CAPACITY (exit 5), never a silent overwrite.
    h_.rows_capacity = 2 * cells;
    h_.cells = cells;
    h_.uid_capacity = uid_capacity;
    auto alloc = [this](auto*& p, size_t n) {
        check(cudaMalloc(reinterpret_cast<void**>(&p), sizeof(*p) * (n ? n : 1)), "allocating the device store");
        owned_.push_back(p);
    };
    const size_t rows = h_.rows_capacity;
    alloc(h_.site_row, cells);
    alloc(h_.target_row, cells);
    alloc(h_.site_sugar, cells);
    alloc(h_.site_spice, cells);
    alloc(h_.buried_key, cells);
    alloc(h_.buried_tags, cells);
    // The uid map is sized by --uid-capacity: a capacity the device cannot hold is a limit, named (exit 5).
    const size_t uid_bytes = sizeof(int) * static_cast<size_t>(uid_capacity);
    if (cudaMalloc(reinterpret_cast<void**>(&h_.uid_row), uid_bytes) != cudaSuccess) {
        cudaGetLastError();  // clear the failed allocation's error
        throw CapacityError("uid capacity " + std::to_string(uid_capacity) + " needs " +
                            std::to_string(uid_bytes >> 20) + " MiB of device memory for the uid map, more than the "
                            "GPU can give: lower --uid-capacity");
    }
    owned_.push_back(h_.uid_row);
    check(cudaMemset(h_.uid_row, 0xFF, uid_bytes), "clearing the uid map");
    for (int** p : {&h_.x, &h_.y, &h_.vision, &h_.metabolism, &h_.age, &h_.max_age, &h_.fertility_start,
                    &h_.fertility_end, &h_.disp_x, &h_.disp_y, &h_.counter, &h_.spice_metabolism, &h_.foresight}) {
        alloc(*p, rows);
    }
    alloc(h_.sugar, rows);
    alloc(h_.initial_sugar, rows);
    alloc(h_.spice, rows);
    alloc(h_.initial_spice, rows);
    alloc(h_.trade_n, rows);
    for (double** p : {&h_.trade_mean, &h_.trade_m2, &h_.trade_sugar, &h_.trade_spice}) alloc(*p, rows);
    alloc(h_.trade_total, 5);
    h_.width = static_cast<unsigned int>(cfg.width);
    for (unsigned int** p : {&h_.loan_first, &h_.loan_count, &h_.n_new}) alloc(*p, rows);
    alloc(h_.loan_entry, static_cast<size_t>(LOANS_PER_CELL) * cells);
    alloc(h_.new_lender, rows * LOAN_SLOTS);
    alloc(h_.new_amount, rows * LOAN_SLOTS);
    alloc(h_.new_due, rows * LOAN_SLOTS);
    alloc(h_.tags, rows);
    alloc(h_.key, rows);
    for (unsigned int** p : {&h_.uid, &h_.sex, &h_.n_children, &h_.parent_a, &h_.parent_b, &h_.n_friends, &h_.moved,
                             &h_.neighbors, &h_.start, &h_.target, &h_.rank, &h_.dead, &h_.done, &h_.ran,
                             &h_.fp_count, &h_.fp_offset, &h_.rank_row, &h_.look_seed, &h_.dir_order}) {
        alloc(*p, rows);
    }
    alloc(h_.newborn_key, rows);
    alloc(h_.death_key, rows);
    alloc(h_.newborn_count, 1);
    alloc(h_.friend_uid, rows * MAX_FRIENDS);
    alloc(h_.friend_dist, rows * MAX_FRIENDS);
    alloc(h_.errors, 1);
    alloc(h_.ran_count, 1);
    alloc(h_.done_count, 1);
    alloc(h_.footprint_miss, 4);
    check(cudaMemset(h_.footprint_miss, 0, 4 * sizeof(unsigned int)), "clearing the footprint check");
    check(cudaMemset(h_.errors, 0, sizeof(unsigned int)), "clearing the store's errors");
    alloc(rank_keys_, rows);
    alloc(rank_keys_sorted_, rows);
    alloc(rank_rows_, rows);
    check(cudaMalloc(reinterpret_cast<void**>(&d_store_), sizeof(Store)), "allocating the device store");
    owned_.push_back(d_store_);
    grow_entries(16 * rows);
}

StoreHost::~StoreHost() {
    for (void* p : owned_) cudaFree(p);
    for (void* p : {static_cast<void*>(entry_key_), static_cast<void*>(entry_key_sorted_), static_cast<void*>(entry_write_),
                    static_cast<void*>(entry_idx_), static_cast<void*>(entry_idx_sorted_), static_cast<void*>(unique_write_),
                    static_cast<void*>(keep_), static_cast<void*>(keep_scan_), static_cast<void*>(start_flag_),
                    static_cast<void*>(h_.entry_pos), static_cast<void*>(h_.unique_key), static_cast<void*>(h_.group_first),
                    static_cast<void*>(h_.group_site), static_cast<void*>(h_.entry_group), temp_}) {
        cudaFree(p);
    }
}

void StoreHost::grow_entries(size_t n) {
    if (n <= entries_capacity_) return;
    n = n + n / 2;
    for (void* p : {static_cast<void*>(entry_key_), static_cast<void*>(entry_key_sorted_), static_cast<void*>(entry_write_),
                    static_cast<void*>(entry_idx_), static_cast<void*>(entry_idx_sorted_), static_cast<void*>(unique_write_),
                    static_cast<void*>(keep_), static_cast<void*>(keep_scan_), static_cast<void*>(start_flag_),
                    static_cast<void*>(h_.entry_pos), static_cast<void*>(h_.unique_key), static_cast<void*>(h_.group_first),
                    static_cast<void*>(h_.group_site), static_cast<void*>(h_.entry_group)}) {
        cudaFree(p);
    }
    auto alloc = [](auto*& p, size_t count) {
        check(cudaMalloc(reinterpret_cast<void**>(&p), sizeof(*p) * count), "allocating footprint entries");
    };
    alloc(entry_key_, n);
    alloc(entry_key_sorted_, n);
    alloc(entry_write_, n);
    alloc(entry_idx_, n);
    alloc(entry_idx_sorted_, n);
    alloc(unique_write_, n);
    alloc(keep_, n);
    alloc(keep_scan_, n);
    alloc(start_flag_, n);
    alloc(h_.entry_pos, n);
    alloc(h_.unique_key, n);
    alloc(h_.group_first, n + 2);
    alloc(h_.group_site, n + 2);
    alloc(h_.entry_group, n);
    entries_capacity_ = n;
}

void StoreHost::prepare(unsigned int n_rows) {
    h_.n_rows = n_rows;
    h_.n_buried = 0;
    check(cudaMemset(h_.newborn_count, 0, sizeof(unsigned int)), "clearing newborn_count");
    check(cudaMemset(h_.site_row, 0xFF, sizeof(int) * h_.cells), "clearing site_row");
    check(cudaMemset(h_.target_row, 0xFF, sizeof(int) * h_.cells), "clearing target_row");
    // Rules T and L: every turn's exchanges and new loans start at none.
    check(cudaMemset(h_.trade_n, 0, sizeof(unsigned int) * n_rows), "clearing the trades");
    check(cudaMemset(h_.n_new, 0, sizeof(unsigned int) * n_rows), "clearing the new loans");
    for (double* p : {h_.trade_mean, h_.trade_m2, h_.trade_sugar, h_.trade_spice}) {
        check(cudaMemset(p, 0, sizeof(double) * n_rows), "clearing the trades");
    }
    check(cudaMemcpy(d_store_, &h_, sizeof(Store), cudaMemcpyHostToDevice), "uploading the store");
}

void StoreHost::schedule(unsigned int n, const RunConfig& cfg) {
    check_errors();
    check(cudaMemset(h_.ran_count, 0, sizeof(unsigned int)), "clearing ran_count");
    check(cudaMemset(h_.done_count, 0, sizeof(unsigned int)), "clearing done_count");
    if (n == 0) return;
    check(cudaMemset(h_.counter, 0, sizeof(int) * n), "clearing counters");
    check(cudaMemset(h_.done, 0, sizeof(unsigned int) * n), "clearing done");
    check(cudaMemset(h_.ran, 0, sizeof(unsigned int) * n), "clearing ran");
    auto temp = [this](size_t bytes) {
        if (bytes > temp_bytes_) {
            cudaFree(temp_);
            check(cudaMalloc(&temp_, bytes), "allocating scheduler scratch");
            temp_bytes_ = bytes;
        }
    };
    size_t bytes = 0;
    // The period's order: rank 0 is the largest key.
    k_rank_keys<<<blocks(n), BLOCK>>>(n, h_.key, rank_keys_, rank_rows_);
    check(cub::DeviceRadixSort::SortPairs(nullptr, bytes, rank_keys_, rank_keys_sorted_, rank_rows_, h_.rank_row, n),
          "sorting on the device");
    temp(bytes);
    check(cub::DeviceRadixSort::SortPairs(temp_, bytes, rank_keys_, rank_keys_sorted_, rank_rows_, h_.rank_row, n),
          "sorting on the device");
    k_ranks<<<blocks(n), BLOCK>>>(n, h_.rank_row, h_);
    // Rule L: each row's loans as borrower, for its footprint and its turn (loans.h).
    if (cfg.credit) loan_index(h_);
    // Footprints: count, offsets, fill.
    const FootprintEnv env{cfg.width, cfg.height, cfg.look_stride, cfg.sex, cfg.mate_contact == "vision", cfg.culture,
                           cfg.combat(), cfg.credit.has_value()};
    k_fp_count<<<blocks(n), BLOCK>>>(n, h_, env);
    bytes = 0;
    check(cub::DeviceScan::ExclusiveSum(nullptr, bytes, h_.fp_count, h_.fp_offset, n), "scanning on the device");
    temp(bytes);
    check(cub::DeviceScan::ExclusiveSum(temp_, bytes, h_.fp_count, h_.fp_offset, n), "scanning on the device");
    unsigned int last_count = 0, last_offset = 0;
    check(cudaMemcpy(&last_count, h_.fp_count + n - 1, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading counts");
    check(cudaMemcpy(&last_offset, h_.fp_offset + n - 1, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading offsets");
    const unsigned int total = last_offset + last_count;
    const size_t before = entries_capacity_;
    grow_entries(total);
    if (entries_capacity_ != before) {
        check(cudaMemcpy(d_store_, &h_, sizeof(Store), cudaMemcpyHostToDevice), "uploading the store");
    }
    k_fp_fill<<<blocks(n), BLOCK>>>(n, h_, env, entry_key_, entry_write_, entry_idx_);
    // Sort by (site, rank); remove duplicates.
    const int end_bit = 32 + bits_for(h_.cells);
    bytes = 0;
    check(cub::DeviceRadixSort::SortPairs(nullptr, bytes, entry_key_, entry_key_sorted_, entry_idx_, entry_idx_sorted_,
                                          total, 0, end_bit),
          "sorting on the device");
    temp(bytes);
    check(cub::DeviceRadixSort::SortPairs(temp_, bytes, entry_key_, entry_key_sorted_, entry_idx_, entry_idx_sorted_,
                                          total, 0, end_bit),
          "sorting on the device");
    // The writes, in sorted order: entry_write_ indexed by fill order, gathered through the sorted indices.
    k_keep<<<blocks(total), BLOCK>>>(total, entry_key_sorted_, keep_);
    bytes = 0;
    check(cub::DeviceScan::ExclusiveSum(nullptr, bytes, keep_, keep_scan_, total), "scanning on the device");
    temp(bytes);
    check(cub::DeviceScan::ExclusiveSum(temp_, bytes, keep_, keep_scan_, total), "scanning on the device");
    // The write flags in sorted order (start_flag_ as scratch until the groups need it).
    k_gather<<<blocks(total), BLOCK>>>(total, entry_idx_sorted_, entry_write_, start_flag_);
    k_compact<<<blocks(total), BLOCK>>>(total, entry_key_sorted_, entry_idx_sorted_, start_flag_, keep_, keep_scan_, h_,
                                        unique_write_);
    unsigned int last_keep = 0, last_scan = 0;
    check(cudaMemcpy(&last_keep, keep_ + total - 1, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading keep");
    check(cudaMemcpy(&last_scan, keep_scan_ + total - 1, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading scan");
    const unsigned int unique = last_scan + last_keep;
    // Groups and the wait counters.
    k_group_starts<<<blocks(unique), BLOCK>>>(unique, h_.unique_key, unique_write_, start_flag_);
    bytes = 0;
    check(cub::DeviceScan::InclusiveSum(nullptr, bytes, start_flag_, h_.entry_group, unique), "scanning on the device");
    temp(bytes);
    check(cub::DeviceScan::InclusiveSum(temp_, bytes, start_flag_, h_.entry_group, unique), "scanning on the device");
    k_groups<<<blocks(unique), BLOCK>>>(unique, start_flag_, h_);
    k_counters<<<blocks(unique), BLOCK>>>(unique, h_);
    h_.n_unique = unique;
    check(cudaMemcpy(d_store_, &h_, sizeof(Store), cudaMemcpyHostToDevice), "uploading the store");
    check(cudaDeviceSynchronize(), "scheduling the turns");
}

std::vector<unsigned int> StoreHost::footprint_misses() {
    std::vector<unsigned int> miss(4);
    check(cudaMemcpy(miss.data(), h_.footprint_miss, 4 * sizeof(unsigned int), cudaMemcpyDeviceToHost),
          "reading the footprint check");
    check(cudaMemset(h_.footprint_miss, 0, 4 * sizeof(unsigned int)), "clearing the footprint check");
    return miss;
}

void StoreHost::wave_counts(unsigned int* ran, unsigned int* done) {
    check(cudaMemcpy(ran, h_.ran_count, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading ran_count");
    check(cudaMemcpy(done, h_.done_count, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading done_count");
    check(cudaMemset(h_.ran_count, 0, sizeof(unsigned int)), "clearing ran_count");
}

namespace {

__global__ void k_newborn_keys(unsigned int n, unsigned int first, const uint64_t* key, uint64_t* keys, unsigned int* rows) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    keys[i] = key[first + i];
    rows[i] = first + i;
}

__global__ void k_newborn_uids(unsigned int n, const unsigned int* sorted_rows, Store s, unsigned int base) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    const unsigned int uid = base + i;
    const unsigned int row = sorted_rows[i];
    s.uid[row] = uid;
    if (uid < s.uid_capacity) s.uid_row[uid] = static_cast<int>(row);
}

// A newborn whose parent was itself born this period names that parent by its row (sex.cuh, PROVISIONAL_PARENT).
__global__ void k_fix_parents(unsigned int n, unsigned int first, Store s) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    for (unsigned int* parent : {s.parent_a + first + i, s.parent_b + first + i}) {
        if (*parent != 0xFFFFFFFFu && (*parent & 0x80000000u)) *parent = s.uid[*parent & 0x7FFFFFFFu];
    }
}

// Friends made of this period's newborns name their rows (culture.cuh, PROVISIONAL_FRIEND) until their uids exist.
__global__ void k_fix_friends(unsigned int n, Store s) {
    const unsigned int r = blockIdx.x * blockDim.x + threadIdx.x;
    if (r >= n) return;
    for (unsigned int f = 0; f < s.n_friends[r]; ++f) {
        unsigned int& ref = s.friend_uid[r * MAX_FRIENDS + f];
        if (ref & 0x80000000u) ref = s.uid[ref & 0x7FFFFFFFu];
    }
}

}  // namespace

unsigned int StoreHost::birth_uids(unsigned int next_uid) {
    check_errors();  // before anything reads a newborn row
    unsigned int n = 0;
    check(cudaMemcpy(&n, h_.newborn_count, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading newborn_count");
    if (n == 0) return 0;
    k_newborn_keys<<<blocks(n), BLOCK>>>(n, h_.n_rows, h_.newborn_key, rank_keys_, rank_rows_);
    size_t bytes = 0;
    check(cub::DeviceRadixSort::SortPairs(nullptr, bytes, rank_keys_, rank_keys_sorted_, rank_rows_, h_.rank_row, n),
          "sorting on the device");
    if (bytes > temp_bytes_) {
        cudaFree(temp_);
        check(cudaMalloc(&temp_, bytes), "allocating scheduler scratch");
        temp_bytes_ = bytes;
    }
    check(cub::DeviceRadixSort::SortPairs(temp_, bytes, rank_keys_, rank_keys_sorted_, rank_rows_, h_.rank_row, n),
          "sorting on the device");
    k_newborn_uids<<<blocks(n), BLOCK>>>(n, h_.rank_row, h_, next_uid);
    k_fix_parents<<<blocks(n), BLOCK>>>(n, h_.n_rows, h_);
    if (h_.n_rows) k_fix_friends<<<blocks(h_.n_rows), BLOCK>>>(h_.n_rows, h_);
    check(cudaDeviceSynchronize(), "assigning newborn uids");
    return n;
}

unsigned int StoreHost::bury() {
    unsigned int n = 0;
    check(cudaMemcpy(&n, h_.newborn_count, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading newborn_count");
    std::vector<std::pair<uint64_t, uint64_t>> buried;  // (death_key, tags)
    if (n) {
        std::vector<unsigned int> dead(n);
        std::vector<uint64_t> key(n), tags(n);
        check(cudaMemcpy(dead.data(), h_.dead + h_.n_rows, n * sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading newborns");
        check(cudaMemcpy(key.data(), h_.death_key + h_.n_rows, n * sizeof(uint64_t), cudaMemcpyDeviceToHost), "reading newborns");
        check(cudaMemcpy(tags.data(), h_.tags + h_.n_rows, n * sizeof(uint64_t), cudaMemcpyDeviceToHost), "reading newborns");
        for (unsigned int i = 0; i < n; ++i) {
            if (dead[i]) buried.emplace_back(key[i], tags[i]);
        }
    }
    if (buried.size() > h_.cells) {
        throw CapacityError(std::to_string(buried.size()) + " newborns killed in one period, more than the " +
                            std::to_string(h_.cells) + " cells that replace them");
    }
    std::sort(buried.begin(), buried.end());
    std::vector<uint64_t> key(buried.size()), tags(buried.size());
    for (size_t i = 0; i < buried.size(); ++i) std::tie(key[i], tags[i]) = buried[i];
    if (!buried.empty()) {
        check(cudaMemcpy(h_.buried_key, key.data(), key.size() * sizeof(uint64_t), cudaMemcpyHostToDevice), "burying newborns");
        check(cudaMemcpy(h_.buried_tags, tags.data(), tags.size() * sizeof(uint64_t), cudaMemcpyHostToDevice), "burying newborns");
    }
    h_.n_buried = static_cast<unsigned int>(buried.size());
    check(cudaMemcpy(d_store_, &h_, sizeof(Store), cudaMemcpyHostToDevice), "uploading the store");
    return h_.n_buried;
}

namespace {

// One thread: the turns' exchange statistics in rank order, merged by Chan's formula (ruling R3).
__global__ void k_trade_totals(unsigned int n, Store s) {
    double count = 0, mean = 0, m2 = 0, sugar = 0, spice = 0;
    for (unsigned int r = 0; r < n; ++r) {
        const unsigned int row = s.rank_row[r];
        const double k = static_cast<double>(s.trade_n[row]);
        if (k == 0) continue;
        const double total = count + k, delta = s.trade_mean[row] - mean;
        mean += delta * k / total;
        m2 += s.trade_m2[row] + delta * delta * count * k / total;
        count = total;
        sugar += s.trade_sugar[row];
        spice += s.trade_spice[row];
    }
    s.trade_total[0] = count;
    s.trade_total[1] = mean;
    s.trade_total[2] = m2;
    s.trade_total[3] = sugar;
    s.trade_total[4] = spice;
}

}  // namespace

TradeTotals StoreHost::trade_totals() {
    k_trade_totals<<<1, 1>>>(h_.n_rows, h_);
    double v[5];
    check(cudaMemcpy(v, h_.trade_total, sizeof(v), cudaMemcpyDeviceToHost), "reading the trades");
    return {v[0], v[1], v[2], v[3], v[4]};
}

void StoreHost::check_errors() {
    unsigned int errors = 0;
    check(cudaMemcpy(&errors, h_.errors, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading the store's errors");
    if (errors & STORE_ROW_CAPACITY) {
        throw CapacityError("the device store's " + std::to_string(h_.rows_capacity) + " rows are full");
    }
    if (errors & STORE_UID_CAPACITY) {
        throw CapacityError("uid capacity " + std::to_string(h_.uid_capacity) +
                            " exceeded: more agents created than --uid-capacity allows");
    }
}

namespace {

__global__ void k_newcomer_uids(unsigned int n, const unsigned int* sorted_slot, unsigned int* uid, unsigned int base) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) uid[sorted_slot[i]] = base + i;
}

}  // namespace

namespace {

__global__ void k_dying_order(unsigned int n, unsigned int* order) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) order[i] = i;
}

__global__ void k_dying_gather(unsigned int n, const unsigned int* sorted_order, const double* posted,
                               const double* posted_spice, Dying d) {
    const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    d.sugar[i] = posted[sorted_order[i]];
    d.spice[i] = posted_spice[sorted_order[i]];
    d.heirs[i] = 0u;
}

}  // namespace

DyingTable::DyingTable(unsigned int cells) {
    auto alloc = [](auto*& p, size_t n) {
        check(cudaMalloc(reinterpret_cast<void**>(&p), sizeof(*p) * (n ? n : 1)), "allocating the dying table");
    };
    alloc(h_.uid, cells);
    alloc(h_.sugar, cells);
    alloc(h_.spice, cells);
    alloc(h_.heirs, cells);
    alloc(h_.count, 1);
    alloc(posted_uid_, cells);
    alloc(posted_sugar_, cells);
    alloc(posted_spice_, cells);
    alloc(order_, cells);
    alloc(sorted_order_, cells);
    check(cudaMemset(h_.count, 0, sizeof(unsigned int)), "clearing the dying table");
    check(cudaMalloc(reinterpret_cast<void**>(&d_), sizeof(Dying)), "allocating the dying table");
    // Posting goes to the posted_* arrays: the device copy names them until sort() swaps in the sorted ones.
    Dying posting = h_;
    posting.uid = posted_uid_;
    posting.sugar = posted_sugar_;
    posting.spice = posted_spice_;
    check(cudaMemcpy(d_, &posting, sizeof(Dying), cudaMemcpyHostToDevice), "uploading the dying table");
}

DyingTable::~DyingTable() {
    for (void* p : {static_cast<void*>(h_.uid), static_cast<void*>(h_.sugar), static_cast<void*>(h_.spice),
                    static_cast<void*>(h_.heirs), static_cast<void*>(h_.count), static_cast<void*>(posted_uid_),
                    static_cast<void*>(posted_sugar_), static_cast<void*>(posted_spice_),
                    static_cast<void*>(order_), static_cast<void*>(sorted_order_), static_cast<void*>(d_), temp_}) {
        cudaFree(p);
    }
}

void DyingTable::sort() {
    unsigned int n = 0;
    check(cudaMemcpy(&n, h_.count, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading the dying count");
    check(cudaMemset(h_.count, 0, sizeof(unsigned int)), "clearing the dying count");
    if (n) {
        k_dying_order<<<blocks(n), BLOCK>>>(n, order_);
        size_t bytes = 0;
        check(cub::DeviceRadixSort::SortPairs(nullptr, bytes, posted_uid_, h_.uid, order_, sorted_order_, n),
              "sorting on the device");
        if (bytes > temp_bytes_) {
            cudaFree(temp_);
            check(cudaMalloc(&temp_, bytes), "allocating dying scratch");
            temp_bytes_ = bytes;
        }
        check(cub::DeviceRadixSort::SortPairs(temp_, bytes, posted_uid_, h_.uid, order_, sorted_order_, n),
              "sorting on the device");
        k_dying_gather<<<blocks(n), BLOCK>>>(n, sorted_order_, posted_sugar_, posted_spice_, h_);
    }
    // The heirs read the sorted table; the next period's dying post to the posted_* arrays again (posting()).
    h_.n = n;
    check(cudaMemcpy(d_, &h_, sizeof(Dying), cudaMemcpyHostToDevice), "uploading the dying table");
    check(cudaDeviceSynchronize(), "sorting the dying");
}

void DyingTable::posting() {
    Dying posting = h_;
    posting.uid = posted_uid_;
    posting.sugar = posted_sugar_;
    posting.spice = posted_spice_;
    posting.n = 0;
    check(cudaMemcpy(d_, &posting, sizeof(Dying), cudaMemcpyHostToDevice), "uploading the dying table");
}

NewcomerUids::NewcomerUids(unsigned int cells) {
    auto alloc = [](auto*& p, size_t n) {
        check(cudaMalloc(reinterpret_cast<void**>(&p), sizeof(*p) * (n ? n : 1)), "allocating newcomer slots");
    };
    h_.capacity = cells;
    alloc(h_.key, cells);
    alloc(h_.slot, cells);
    alloc(h_.uid, cells);
    alloc(h_.count, 1);
    alloc(sorted_key_, cells);
    alloc(sorted_slot_, cells);
    check(cudaMemset(h_.count, 0, sizeof(unsigned int)), "clearing newcomer slots");
    check(cudaMalloc(reinterpret_cast<void**>(&d_slots_), sizeof(NewcomerSlots)), "allocating newcomer slots");
    check(cudaMemcpy(d_slots_, &h_, sizeof(NewcomerSlots), cudaMemcpyHostToDevice), "uploading newcomer slots");
}

NewcomerUids::~NewcomerUids() {
    for (void* p : {static_cast<void*>(h_.key), static_cast<void*>(h_.slot), static_cast<void*>(h_.uid),
                    static_cast<void*>(h_.count), static_cast<void*>(sorted_key_), static_cast<void*>(sorted_slot_),
                    static_cast<void*>(d_slots_), temp_}) {
        cudaFree(p);
    }
}

unsigned int NewcomerUids::assign(unsigned int next_uid) {
    unsigned int n = 0;
    check(cudaMemcpy(&n, h_.count, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading newcomer count");
    check(cudaMemset(h_.count, 0, sizeof(unsigned int)), "clearing newcomer count");
    if (n == 0) return 0;
    // More newcomers than cells (deaths in a near-full world, with newborns killed in combat): there are not the empty
    // sites to place them either, so the run stops here with the limit named.
    if (n > h_.capacity) {
        throw CapacityError(std::to_string(n) + " newcomers in one period, more than the " +
                            std::to_string(h_.capacity) + " cells that can hold them");
    }
    size_t bytes = 0;
    check(cub::DeviceRadixSort::SortPairs(nullptr, bytes, h_.key, sorted_key_, h_.slot, sorted_slot_, n),
          "sorting on the device");
    if (bytes > temp_bytes_) {
        cudaFree(temp_);
        check(cudaMalloc(&temp_, bytes), "allocating newcomer scratch");
        temp_bytes_ = bytes;
    }
    check(cub::DeviceRadixSort::SortPairs(temp_, bytes, h_.key, sorted_key_, h_.slot, sorted_slot_, n),
          "sorting on the device");
    k_newcomer_uids<<<blocks(n), BLOCK>>>(n, sorted_slot_, h_.uid, next_uid);
    check(cudaDeviceSynchronize(), "assigning newcomer uids");
    return n;
}
