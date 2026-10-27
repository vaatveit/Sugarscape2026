// Trade T in the turn, line for line with Python's sugarscape.rules.trade (pp.101-107, App. B p.184; plan
// 2026-10-26-gpu-parity-part-c, Task 5). Each turn keeps its own price statistics (Welford on ln p), which
// StoreHost::trade_totals combines in rank order (ruling R3). Included only by model.cu (via turn.cuh).
#ifndef SRC_TRADE_CUH_
#define SRC_TRADE_CUH_

#include "disease.cuh"
#include "looks.cuh"
#include "rules.cuh"
#include "store.h"
#include "welfare.h"

__device__ __forceinline__ bool valid_mrs(double v) { return is_finite(v) && v > 0.0; }

// Python bargain(a, b): while the MRSs differ, the higher-MRS agent buys sugar with spice at the geometric mean of the
// MRSs (eq. 4), p spice for 1 sugar (p > 1) or 1 spice for 1/p sugar (p < 1), whole units with `whole`; an exchange
// stands only if both welfares strictly rise, every holding stays positive and the MRSs don't cross (fn 17). Each
// exchange is logged in the row `owner`'s statistics: the turn's.
__device__ void bargain(const Store& s, int a, int b, bool cultural, bool whole, int tag_length, unsigned int owner,
                        double fee) {
    const double fa = preference_fraction(s.tags[a], tag_length, cultural);
    const double fb = preference_fraction(s.tags[b], tag_length, cultural);
    // Each side's sugar_burn now (disease.cuh): the metabolism plus its disease fees (Python's welfare and mrs).
    auto mrs_of = [&](int r, double f) {
        return mrs(sugar_burn(s, static_cast<unsigned int>(r), fee), s.spice_metabolism[r], f, s.sugar[r], s.spice[r]);
    };
    auto welfare_of = [&](int r, double f) {
        return welfare(sugar_burn(s, static_cast<unsigned int>(r), fee), s.spice_metabolism[r], f, s.sugar[r], s.spice[r]);
    };
    while (true) {
        const double ma = mrs_of(a, fa), mb = mrs_of(b, fb);
        if (!(valid_mrs(ma) && valid_mrs(mb)) || ma == mb) return;
        const bool a_high = ma > mb;
        const int hi = a_high ? a : b, lo = a_high ? b : a;
        const double fh = a_high ? fa : fb, fl = a_high ? fb : fa;
        const double price = sqrt(ma * mb);
        double sugar = 1.0, spice = 1.0;
        if (price > 1.0) {
            spice = price;
        } else if (price < 1.0) {
            sugar = 1.0 / price;
        }
        if (whole) {
            sugar = floor(sugar);
            spice = floor(spice);
        }
        const double old[4] = {s.sugar[hi], s.spice[hi], s.sugar[lo], s.spice[lo]};
        const double before_hi = welfare_of(hi, fh), before_lo = welfare_of(lo, fl);
        s.sugar[hi] += sugar;
        s.spice[hi] -= spice;
        s.sugar[lo] -= sugar;
        s.spice[lo] += spice;
        const bool accepted = fmin(fmin(s.sugar[hi], s.spice[hi]), fmin(s.sugar[lo], s.spice[lo])) > 0.0 &&
                              welfare_of(hi, fh) > before_hi && welfare_of(lo, fl) > before_lo &&
                              mrs_of(hi, fh) >= mrs_of(lo, fl);  // no crossing over
        if (!accepted) {
            s.sugar[hi] = old[0];
            s.spice[hi] = old[1];
            s.sugar[lo] = old[2];
            s.spice[lo] = old[3];
            return;
        }
        // The exchange, in the turn's statistics (Welford's update of ln p's mean and M2).
        const double x = log(price);
        const unsigned int n = ++s.trade_n[owner];
        const double delta = x - s.trade_mean[owner];
        s.trade_mean[owner] += delta / static_cast<double>(n);
        s.trade_m2[owner] += delta * (x - s.trade_mean[owner]);
        s.trade_sugar[owner] += sugar;
        s.trade_spice[owner] += spice;
    }
}

// Python trade_with_neighbors: once with each agent on the four sites around it now (after mating and culture, so
// newborns too), in a random order.
template <typename API>
__device__ void trade_with_neighbors(API* FLAMEGPU, const Store& s, unsigned int row) {
    const auto& env = FLAMEGPU->environment;
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    const bool cultural = env.template getProperty<unsigned int>("cultural_preferences") != 0u;
    const bool whole = env.template getProperty<unsigned int>("trade_down") != 0u;
    const int tag_length = static_cast<int>(env.template getProperty<unsigned int>("tag_length"));
    const int a = static_cast<int>(row);
    int neighbours[4];
    int n = 0;
    for (int d = 0; d < 4; ++d) {
        const unsigned int site = static_cast<unsigned int>(wrap(s.x[a] + dir_dx(d), w) + wrap(s.y[a] + dir_dy(d), h) * w);
        touch(s, site, s.rank[a], 10);
        if (s.site_row[site] >= 0) neighbours[n++] = s.site_row[site];
    }
    for (int i = n - 1; i > 0; --i) {  // rng.permutation
        const int j = draw_between(FLAMEGPU, 0, i);
        const int t = neighbours[i];
        neighbours[i] = neighbours[j];
        neighbours[j] = t;
    }
    const double fee = env.template getProperty<double>("disease_fee");
    for (int i = 0; i < n; ++i) bargain(s, a, neighbours[i], cultural, whole, tag_length, row, fee);
}

#endif  // SRC_TRADE_CUH_
