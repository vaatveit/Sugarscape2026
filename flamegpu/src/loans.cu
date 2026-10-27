#include "loans.h"

#include <string>

#include "book.cuh"
#include "store.h"

namespace {

void check(cudaError_t e, const char* what) {
    if (e != cudaSuccess) throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(e));
}

__device__ __forceinline__ int row_of(const Store& s, unsigned int uid) {
    if (uid >= s.uid_capacity) return -1;
    const int r = s.uid_row[uid];
    return r >= 0 && static_cast<unsigned int>(r) < s.n_rows && s.uid[r] == uid ? r : -1;
}

// One thread (the book holds hundreds of loans, thousands at xl): each loan's rows, then each borrower's loans in list
// order. loan_count is the cursor while filling.
__global__ void k_loan_index(Store s) {
    const Loans& b = s.book;
    const unsigned int n = *b.n;
    for (unsigned int r = 0; r < s.n_rows; ++r) s.loan_count[r] = 0u;
    for (unsigned int e = 0; e < n; ++e) {
        b.lender_row[e] = row_of(s, b.lender[e]);
        b.borrower_row[e] = row_of(s, b.borrower[e]);
        if (b.borrower_row[e] >= 0) ++s.loan_count[b.borrower_row[e]];
    }
    unsigned int first = 0;
    for (unsigned int r = 0; r < s.n_rows; ++r) {
        s.loan_first[r] = first;
        first += s.loan_count[r];
        s.loan_count[r] = 0u;
    }
    for (unsigned int e = 0; e < n; ++e) {
        const int r = b.borrower_row[e];
        if (r >= 0) s.loan_entry[s.loan_first[r] + s.loan_count[r]++] = e;
    }
}

// One thread, after the turns (Python's list after them, without inheritance): the start-of-period loans whose lender
// and borrower both live, in order (a death's on_death drops its loans either way), then the turns' new loans, turns
// in rank order and each turn's in the order made, but those whose lender starved later in the period.
__global__ void k_rebuild_loans(Store s, int due_t) {
    const Loans& b = s.book;
    const unsigned int n = *b.n;
    unsigned int w = 0;
    for (unsigned int e = 0; e < n; ++e) {
        const int lr = b.lender_row[e], br = b.borrower_row[e];
        if (lr < 0 || br < 0 || s.dead[lr] || s.dead[br]) continue;
        if (w != e) book_put(b, w, b.lender[e], b.borrower[e], b.principal[e], b.due[e], b.due_t[e]);
        ++w;
    }
    for (unsigned int k = 0; k < s.n_rows; ++k) {
        const unsigned int row = s.rank_row[k];
        if (s.dead[row]) continue;
        for (unsigned int j = 0; j < s.n_new[row]; ++j) {
            const unsigned int slot = row * LOAN_SLOTS + j;
            const int lender = s.new_lender[slot];
            if (s.dead[lender]) continue;
            if (book_put(b, w, s.uid[lender], s.uid[row], s.new_amount[slot], s.new_due[slot], due_t)) ++w;
        }
    }
    *b.n = w;
}

// One thread, the end of the period, as Python's Model.step runs it after aging:
// 1. on_death for the dying of old age, in uid order: without inheritance each one's loans go, as lender or borrower;
//    with it a lender's loans pass to its living children that aren't dying (DyingTable's pairs, in uid order);
// 2. settle_loans: the loans due now, in list order, each removed and repaid in full if the borrower can, else half
//    its positive sugar paid and the rest originated anew at the end of the list, on the same terms.
// Sugar moves in ledger_sugar, indexed by uid_row (ledger_post).
__global__ void k_ledger(Store s, Dying d, int t, int duration, double rate, bool inheritance) {
    const Loans& b = s.book;
    unsigned int n = *b.n, w = 0;
    if (inheritance) {
        unsigned int first = 0;
        for (unsigned int i = 0; i < d.n; ++i) {
            const unsigned int uid = d.uid[i];
            while (first < d.n_pairs && (d.pair_sorted[first] >> 32) < uid) ++first;
            unsigned int end = first;
            while (end < d.n_pairs && (d.pair_sorted[end] >> 32) == uid) ++end;
            book_on_death(b, uid, d.pair_child + first, end - first);
            first = end;
        }
        n = *b.n;
    } else {
        for (unsigned int e = 0; e < n; ++e) {
            if (find_dying(d, b.lender[e]) >= 0 || find_dying(d, b.borrower[e]) >= 0) continue;
            if (w != e) book_put(b, w, b.lender[e], b.borrower[e], b.principal[e], b.due[e], b.due_t[e]);
            ++w;
        }
        n = w;
    }
    // The re-originated loans wait past the book's end (at n + k, never below the read position), then join it.
    unsigned int reborn = 0;
    w = 0;
    for (unsigned int e = 0; e < n; ++e) {
        if (b.due_t[e] != t) {
            if (w != e) book_put(b, w, b.lender[e], b.borrower[e], b.principal[e], b.due[e], b.due_t[e]);
            ++w;
            continue;
        }
        const int bi = s.uid_row[b.borrower[e]], li = s.uid_row[b.lender[e]];
        double& borrower = b.ledger_sugar[bi];
        double& lender = b.ledger_sugar[li];
        if (borrower >= b.due[e]) {
            borrower -= b.due[e];
            lender += b.due[e];
            continue;
        }
        const double paid = (borrower > 0.0 ? borrower : 0.0) / 2;
        borrower -= paid;
        lender += paid;
        const double rest = b.due[e] - paid;
        if (book_put(b, n + reborn, b.lender[e], b.borrower[e], rest, rest * (1 + rate / 100 * duration), t + duration)) {
            ++reborn;
        }
    }
    for (unsigned int k = 0; k < reborn; ++k, ++w) {
        const unsigned int e = n + k;
        book_put(b, w, b.lender[e], b.borrower[e], b.principal[e], b.due[e], b.due_t[e]);
    }
    *b.n = w;
}

}  // namespace

LoanBook::LoanBook(unsigned int cells, unsigned int rows) {
    h_.capacity = LOANS_PER_CELL * cells;
    auto alloc = [](auto*& p, size_t count) {
        check(cudaMalloc(reinterpret_cast<void**>(&p), sizeof(*p) * (count ? count : 1)), "allocating the loan book");
    };
    alloc(h_.n, 1);
    alloc(h_.errors, 1);
    alloc(h_.lender, h_.capacity);
    alloc(h_.borrower, h_.capacity);
    alloc(h_.principal, h_.capacity);
    alloc(h_.due, h_.capacity);
    alloc(h_.due_t, h_.capacity);
    alloc(h_.lender_row, h_.capacity);
    alloc(h_.borrower_row, h_.capacity);
    alloc(h_.ledger_sugar, rows);
    check(cudaMemset(h_.n, 0, sizeof(unsigned int)), "clearing the loan book");
    check(cudaMemset(h_.errors, 0, sizeof(unsigned int)), "clearing the loan book");
}

LoanBook::~LoanBook() {
    for (void* p : {static_cast<void*>(h_.n), static_cast<void*>(h_.errors), static_cast<void*>(h_.lender),
                    static_cast<void*>(h_.borrower), static_cast<void*>(h_.principal), static_cast<void*>(h_.due),
                    static_cast<void*>(h_.due_t), static_cast<void*>(h_.lender_row), static_cast<void*>(h_.borrower_row),
                    static_cast<void*>(h_.ledger_sugar)}) {
        cudaFree(p);
    }
}

std::vector<LoanRecord> LoanBook::to_host() const {
    unsigned int n = 0;
    check(cudaMemcpy(&n, h_.n, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading the loan book");
    std::vector<uint32_t> lender(n), borrower(n);
    std::vector<double> principal(n), due(n);
    std::vector<int> due_t(n);
    if (n) {
        check(cudaMemcpy(lender.data(), h_.lender, n * sizeof(uint32_t), cudaMemcpyDeviceToHost), "reading the loan book");
        check(cudaMemcpy(borrower.data(), h_.borrower, n * sizeof(uint32_t), cudaMemcpyDeviceToHost), "reading the loan book");
        check(cudaMemcpy(principal.data(), h_.principal, n * sizeof(double), cudaMemcpyDeviceToHost), "reading the loan book");
        check(cudaMemcpy(due.data(), h_.due, n * sizeof(double), cudaMemcpyDeviceToHost), "reading the loan book");
        check(cudaMemcpy(due_t.data(), h_.due_t, n * sizeof(int), cudaMemcpyDeviceToHost), "reading the loan book");
    }
    std::vector<LoanRecord> out(n);
    for (unsigned int i = 0; i < n; ++i) out[i] = {lender[i], borrower[i], principal[i], due[i], due_t[i]};
    return out;
}

void LoanBook::check_errors() const {
    unsigned int errors = 0;
    check(cudaMemcpy(&errors, h_.errors, sizeof(unsigned int), cudaMemcpyDeviceToHost), "reading the loan book");
    if (errors & LOAN_CAPACITY_ERROR) {
        throw CapacityError("loan book capacity " + std::to_string(h_.capacity) + " exceeded (" +
                            std::to_string(LOANS_PER_CELL) + " loans per cell)");
    }
}

void loan_index(const Store& s) {
    k_loan_index<<<1, 1>>>(s);
    check(cudaDeviceSynchronize(), "indexing the loan book");
}

void rebuild_loans(const Store& s, int due_t) {
    k_rebuild_loans<<<1, 1>>>(s, due_t);
    check(cudaDeviceSynchronize(), "rebuilding the loan book");
}

void run_ledger(const Store& s, const Dying& d, int t, int duration, double rate, bool inheritance) {
    k_ledger<<<1, 1>>>(s, d, t, duration, rate, inheritance);
    check(cudaDeviceSynchronize(), "settling the loans");
}
