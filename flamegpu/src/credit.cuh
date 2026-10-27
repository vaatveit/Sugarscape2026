// Credit L in the turn, line for line with Python's sugarscape.rules.credit (pp.131-133, App. B pp.184-185; plan
// 2026-10-26-gpu-parity-part-c, Task 6). Included only by model.cu (via turn.cuh).
#ifndef SRC_CREDIT_CUH_
#define SRC_CREDIT_CUH_

#include "looks.cuh"
#include "model.h"
#include "rules.cuh"
#include "store.h"

// Python available_to_lend: too old to have children, half its wealth; of childbearing age, the wealth beyond what a
// child needs (its own initial endowment, scaled by the fertility threshold); otherwise nothing (p.132).
__device__ __forceinline__ double available_to_lend(const Store& s, int r, double threshold) {
    if (s.sex[r] == SEX_NONE || s.sugar[r] <= 0.0) return 0.0;
    if (s.age[r] >= s.fertility_end[r]) return s.sugar[r] / 2;
    const double need = threshold * s.initial_sugar[r];
    if (s.fertility_start[r] <= s.age[r] && s.sugar[r] > need) return s.sugar[r] - need;
    return 0.0;
}

// Python shortfall: of childbearing age without the wealth to have a child, how much it lacks.
__device__ __forceinline__ double shortfall(const Store& s, int r, double threshold) {
    if (s.sex[r] == SEX_NONE || !(s.fertility_start[r] <= s.age[r] && s.age[r] < s.fertility_end[r])) return 0.0;
    const double lack = threshold * s.initial_sugar[r] - s.sugar[r];
    return lack > 0.0 ? lack : 0.0;
}

// Python seek_credit: a potential borrower asks each neighbour in turn, in a random order, for the sugar it needs.
// A loan needs the borrower creditworthy: its income this period (harvest minus metabolism) over the loan's duration
// covers this loan's due plus what it already owes. Owed is Python's sum in list order: the borrower's start-of-period
// loans whose lender still lives at this turn (a lender that starved earlier in the order voided them; its site is in
// this turn's footprint), then this turn's new loans. A loan is kept in the borrower's row (rebuild_loans).
template <typename API>
__device__ void seek_credit(API* FLAMEGPU, const Store& s, unsigned int row, double last_income) {
    const auto& env = FLAMEGPU->environment;
    const double threshold = env.template getProperty<double>("fertility_threshold");
    const int a = static_cast<int>(row);
    double need = shortfall(s, a, threshold);
    if (need <= 0.0) return;
    const int duration = env.template getProperty<int>("credit_duration");
    const double rate = env.template getProperty<double>("credit_rate");
    const int w = static_cast<int>(env.template getProperty<unsigned int>("width"));
    const int h = static_cast<int>(env.template getProperty<unsigned int>("height"));
    int neighbours[4];
    int n = 0;
    for (int d = 0; d < 4; ++d) {
        const unsigned int site = static_cast<unsigned int>(wrap(s.x[a] + dir_dx(d), w) + wrap(s.y[a] + dir_dy(d), h) * w);
        touch(s, site, s.rank[a], 11);
        if (s.site_row[site] >= 0) neighbours[n++] = s.site_row[site];
    }
    for (int i = n - 1; i > 0; --i) {  // rng.permutation
        const int j = draw_between(FLAMEGPU, 0, i);
        const int t = neighbours[i];
        neighbours[i] = neighbours[j];
        neighbours[j] = t;
    }
    double owed = 0.0;
    bool owed_known = false;  // Python sums only when a lender offers something
    for (int i = 0; i < n; ++i) {
        const int lender = neighbours[i];
        const double offer = available_to_lend(s, lender, threshold);
        const double amount = offer < need ? offer : need;
        if (amount <= 0.0) continue;
        if (!owed_known) {
            const unsigned int first = s.loan_first[a], end = first + s.loan_count[a];
            for (unsigned int k = first; k < end; ++k) {
                const unsigned int e = s.loan_entry[k];
                const int lr = s.book.lender_row[e];
                touch_row(s, static_cast<unsigned int>(lr), s.rank[a], 13);
                if (!s.dead[lr]) owed += s.book.due[e];
            }
            for (unsigned int k = 0; k < s.n_new[a]; ++k) owed += s.new_due[row * LOAN_SLOTS + k];
            owed_known = true;
        }
        const double amount_due = amount * (1 + rate / 100 * duration);
        if (!(last_income * duration - owed >= amount_due)) continue;
        s.sugar[lender] -= amount;
        s.sugar[a] += amount;
        const unsigned int slot = row * LOAN_SLOTS + s.n_new[a]++;
        s.new_lender[slot] = lender;
        s.new_amount[slot] = amount;
        s.new_due[slot] = amount_due;
        owed += amount_due;
        need -= amount;
        if (need <= 0.0) break;
    }
}

#endif  // SRC_CREDIT_CUH_
