// Rule S in the turn, line for line with Python's sugarscape.rules.sex (pp.55-57; spec 2026-10-25-gpu-full-parity,
// section 4). Included only by model.cu (via turn.cuh).
#ifndef SRC_SEX_CUH_
#define SRC_SEX_CUH_

#include "looks.cuh"
#include "model.h"
#include "rules.cuh"
#include "store.h"

// The most partners a turn considers: four lines of looks (validate() bounds vision / look_stride).
constexpr int MAX_PARTNERS = 4 * MAX_SIGHT_LOOKS;
constexpr double GIFT_CAP = 5.0;  // Ascape's most a parent gives a child (child_gift = "capped")

// Of childbearing age and holding at least the share of its birth endowment the threshold asks (p.55).
__device__ __forceinline__ bool is_fertile(const Store& s, int r, double threshold) {
    return s.sex[r] != SEX_NONE && s.fertility_start[r] <= s.age[r] && s.age[r] < s.fertility_end[r] &&
           s.sugar[r] >= threshold * s.initial_sugar[r];
}

__device__ __forceinline__ unsigned int site_of(int x, int y, int w, int h) {
    return static_cast<unsigned int>(wrap(x, w) + wrap(y, h) * w);
}

// Python's _empty_sites: the agent's four neighbouring sites, in VON_NEUMANN order, that are empty, and not the
// target of an agent still to come this period (spec section 8, difference 2).
__device__ __forceinline__ int add_empty_sites(const Store& s, int r, int w, int h, unsigned int* sites, int n,
                                               unsigned int rank) {
    for (int d = 0; d < 4; ++d) {
        const unsigned int site = site_of(s.x[r] + dir_dx(d), s.y[r] + dir_dy(d), w, h);
        touch(s, site, rank, 4);
        if (s.site_row[site] >= 0) continue;
        const int mover = s.target_row[site];
        if (mover >= 0 && !s.done[mover]) continue;
        bool seen = false;  // dict.fromkeys: the agent's sites first, each once
        for (int i = 0; i < n; ++i) seen = seen || sites[i] == site;
        if (!seen) sites[n++] = site;
    }
    return n;
}

template <typename API>
__device__ __forceinline__ unsigned int sex_draw(API* FLAMEGPU) {
    return draw_between(FLAMEGPU, 0, 1) == 0 ? SEX_F : SEX_M;
}

// Rule S for the row's agent (Python sex.mate): each partner in random order; a child for each fertile pair of
// opposite sexes with an empty site next to either.
template <typename API>
__device__ void mate(API* FLAMEGPU, const Store& s, unsigned int row) {
    const auto& env = FLAMEGPU->environment;
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    const int stride = static_cast<int>(env.template getProperty<unsigned int>("look_stride"));
    const double threshold = env.template getProperty<double>("fertility_threshold");
    const double share = env.template getProperty<double>("child_share");
    const bool capped = env.template getProperty<unsigned int>("child_capped") != 0u;
    const bool redraw = env.template getProperty<unsigned int>("child_redraw") != 0u;
    const bool rounded = env.template getProperty<unsigned int>("gift_down") != 0u;
    const int tag_length = static_cast<int>(env.template getProperty<unsigned int>("tag_length"));
    const int a = static_cast<int>(row);
    // Outside childbearing age no partner can be fertile with it, and its footprint (footprint.cuh) holds no sight
    // lines: return before looking. Python still draws the permutation here; the GPU's stream is its own.
    if (s.sex[a] == SEX_NONE || !(s.fertility_start[a] <= s.age[a] && s.age[a] < s.fertility_end[a])) return;

    // Partners: in sight along the lattice (Python in_sight), each distance looked at once, or the four neighbours in
    // VON_NEUMANN order. Python lists them nearest first; the permutation below makes the listing order irrelevant.
    int partners[MAX_PARTNERS];
    int n = 0;
    if (env.template getProperty<unsigned int>("mate_vision")) {
        const int looks = s.vision[a] / stride;
        for (int k = 0; k < looks; ++k) {
            for (int d = 0; d < 4; ++d) {
                if (repeated_look(s.look_seed[a] ^ SIGHT_SALT, d, k, stride)) continue;  // one partner, seen once
                const int dist = sight_distance(s.look_seed[a], d, k, stride);
                const unsigned int site = site_of(s.x[a] + dir_dx(d) * dist, s.y[a] + dir_dy(d) * dist, w, h);
                touch(s, site, s.rank[a], 3);
                const int other = s.site_row[site];
                if (other >= 0) partners[n++] = other;
            }
        }
    } else {
        for (int d = 0; d < 4; ++d) {
            const int other = s.site_row[site_of(s.x[a] + dir_dx(d), s.y[a] + dir_dy(d), w, h)];
            if (other >= 0) partners[n++] = other;
        }
    }
    // rng.permutation(len(neighbors)) (Fisher-Yates).
    for (int i = n - 1; i > 0; --i) {
        const int j = draw_between(FLAMEGPU, 0, i);
        const int t = partners[i];
        partners[i] = partners[j];
        partners[j] = t;
    }
    unsigned int seq = 0;
    for (int i = 0; i < n; ++i) {
        const int b = partners[i];
        if (s.sex[b] == SEX_NONE || s.sex[b] == s.sex[a] || !(is_fertile(s, a, threshold) && is_fertile(s, b, threshold))) {
            continue;
        }
        unsigned int sites[8];
        const unsigned int rank = s.rank[a];
        const int m = add_empty_sites(s, b, w, h, sites, add_empty_sites(s, a, w, h, sites, 0, rank), rank);
        if (m == 0) continue;
        const unsigned int site = sites[draw_between(FLAMEGPU, 0, m - 1)];
        const int parents[2] = {a, b};
        const int vision = s.vision[parents[draw_between(FLAMEGPU, 0, 1)]];
        const int metabolism = s.metabolism[parents[draw_between(FLAMEGPU, 0, 1)]];
        const int max_age = s.max_age[parents[draw_between(FLAMEGPU, 0, 1)]];
        double gifts[2];
        for (int p = 0; p < 2; ++p) {
            const int q = parents[p];
            gifts[p] = capped ? fmin(GIFT_CAP, fmax(s.sugar[q], 0.0)) : s.initial_sugar[q] * share;
            if (rounded) gifts[p] = floor(gifts[p]);
        }
        s.sugar[a] -= gifts[0];
        s.sugar[b] -= gifts[1];
        // The child: a newborn row, placed now so the rest of the period sees it.
        const unsigned int slot = s.n_rows + atomicAdd(s.newborn_count, 1u);
        if (slot >= s.rows_capacity) {  // never with rows for 2 x cells (store.cu); a store fault, not a silent overwrite
            atomicOr(s.errors, STORE_ROW_CAPACITY);
            return;
        }
        const int c = static_cast<int>(slot);
        s.x[c] = static_cast<int>(site % static_cast<unsigned int>(w));
        s.y[c] = static_cast<int>(site / static_cast<unsigned int>(w));
        s.vision[c] = vision;
        s.metabolism[c] = metabolism;
        s.max_age[c] = max_age;
        s.age[c] = 0;
        s.sugar[c] = gifts[0] + gifts[1];
        s.initial_sugar[c] = redraw ? static_cast<double>(draw_between(FLAMEGPU, env.template getProperty<int>("endowment_lo"),
                                                                       env.template getProperty<int>("endowment_hi")))
                                    : gifts[0] + gifts[1];
        const unsigned int sex = sex_draw(FLAMEGPU);  // Python's _assign_sex: sex, then childbearing ages for it
        s.sex[c] = sex;
        s.fertility_start[c] = draw_between(FLAMEGPU, env.template getProperty<int>("fertility_start_lo"),
                                            env.template getProperty<int>("fertility_start_hi"));
        s.fertility_end[c] = sex == SEX_F ? draw_between(FLAMEGPU, env.template getProperty<int>("female_fertility_end_lo"),
                                                         env.template getProperty<int>("female_fertility_end_hi"))
                                          : draw_between(FLAMEGPU, env.template getProperty<int>("male_fertility_end_lo"),
                                                         env.template getProperty<int>("male_fertility_end_hi"));
        // Vertical transmission (p.78): agreeing positions copy, the others take a fair coin.
        uint64_t tags = 0;
        if (tag_length) {
            for (int t = 0; t < tag_length; ++t) {
                const uint64_t ta = (s.tags[a] >> t) & 1u, tb = (s.tags[b] >> t) & 1u;
                tags |= (ta == tb ? ta : static_cast<uint64_t>(draw_between(FLAMEGPU, 0, 1))) << t;
            }
        }
        s.tags[c] = tags;
        // Chapter IV, after the tags as Python draws it: each parent gives half its initial spice (or capped), the
        // child's initial spice may be redrawn, and its spice metabolism and foresight come each from a random parent.
        s.spice[c] = 0.0;
        s.initial_spice[c] = 0.0;
        s.spice_metabolism[c] = 0;
        s.foresight[c] = 0;
        if (env.template getProperty<unsigned int>("spice")) {
            double spice_gifts[2];
            for (int p = 0; p < 2; ++p) {
                const int q = parents[p];
                spice_gifts[p] = capped ? fmin(GIFT_CAP, fmax(s.spice[q], 0.0)) : s.initial_spice[q] * share;
                if (rounded) spice_gifts[p] = floor(spice_gifts[p]);
            }
            s.spice[a] -= spice_gifts[0];
            s.spice[b] -= spice_gifts[1];
            s.spice[c] = s.initial_spice[c] = spice_gifts[0] + spice_gifts[1];
            if (redraw) {
                s.initial_spice[c] = static_cast<double>(draw_between(FLAMEGPU, env.template getProperty<int>("spice_endowment_lo"),
                                                                      env.template getProperty<int>("spice_endowment_hi")));
            }
            s.spice_metabolism[c] = s.spice_metabolism[parents[draw_between(FLAMEGPU, 0, 1)]];
            s.foresight[c] = s.foresight[parents[draw_between(FLAMEGPU, 0, 1)]];
        }
        // Chapter V, last: the parents' untrained genotypes are crossed as the tags are (p.146); the phenotype copies
        // the child's, and it carries no disease.
        uint64_t genotype = 0;
        if (env.template getProperty<unsigned int>("disease")) {
            const int immune_length = static_cast<int>(env.template getProperty<unsigned int>("immune_length"));
            for (int i = 0; i < immune_length; ++i) {
                const uint64_t ga = (s.immune_genotype[a] >> i) & 1u, gb = (s.immune_genotype[b] >> i) & 1u;
                genotype |= (ga == gb ? ga : static_cast<uint64_t>(draw_between(FLAMEGPU, 0, 1))) << i;
            }
        }
        s.immune_genotype[c] = genotype;
        s.immune[c] = genotype;
        s.n_diseases[c] = 0u;
        s.uid[c] = NO_UID;  // given in creation order after the turns (StoreHost::birth_uids)
        s.n_children[c] = 0u;
        // A parent born this period (possible with fertility from age 0) has no uid yet: name it by its row, marked, until
        // StoreHost::birth_uids writes the uid in (as culture.cuh does for friends).
        s.parent_a[c] = s.uid[a] == NO_UID ? (PROVISIONAL_PARENT | static_cast<unsigned int>(a)) : s.uid[a];
        s.parent_b[c] = s.uid[b] == NO_UID ? (PROVISIONAL_PARENT | static_cast<unsigned int>(b)) : s.uid[b];
        s.n_friends[c] = 0u;
        s.disp_x[c] = 0;
        s.disp_y[c] = 0;
        s.moved[c] = 0u;
        s.neighbors[c] = 0u;
        s.dead[c] = 0u;
        s.done[c] = 1u;  // a newborn takes no turn this period
        s.newborn_key[c] = (static_cast<uint64_t>(s.rank[a]) << 32) | seq++;
        s.site_row[site] = c;
        auto occupied = env.template getMacroProperty<unsigned int, MAX_CELLS>("occupied");
        occupied[site].exchange(1u);
        ++s.n_children[a];
        ++s.n_children[b];
    }
}

#endif  // SRC_SEX_CUH_
