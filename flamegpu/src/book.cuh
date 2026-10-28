// Python's list operations on the loan book, for one device thread at a time: the after-turns rebuild and the ledger
// (loans.cu), and with inheritance the turns themselves, which then run one per wave (plan
// 2026-10-26-gpu-parity-part-c, Task 7). Included by loans.cu and credit.cuh.
#ifndef SRC_BOOK_CUH_
#define SRC_BOOK_CUH_

#include "loans.h"

__device__ __forceinline__ bool book_put(const Loans& b, unsigned int at, unsigned int lender, unsigned int borrower,
                                         double principal, double due, int due_t) {
    if (at >= b.capacity) {
        atomicOr(b.errors, LOAN_CAPACITY_ERROR);
        return false;
    }
    b.lender[at] = lender;
    b.borrower[at] = borrower;
    b.principal[at] = principal;
    b.due[at] = due;
    b.due_t[at] = due_t;
    return true;
}

// Entry `at` of the staging list (Loans' stage_*), which has the book's capacity.
__device__ __forceinline__ bool stage_put(const Loans& b, unsigned int at, unsigned int lender, unsigned int borrower,
                                          double principal, double due, int due_t) {
    if (at >= b.capacity) {
        atomicOr(b.errors, LOAN_CAPACITY_ERROR);
        return false;
    }
    b.stage_lender[at] = lender;
    b.stage_borrower[at] = borrower;
    b.stage_principal[at] = principal;
    b.stage_due[at] = due;
    b.stage_due_t[at] = due_t;
    return true;
}

// Staged entry `from` into the book at `at`.
__device__ __forceinline__ bool book_from_stage(const Loans& b, unsigned int at, unsigned int from) {
    return book_put(b, at, b.stage_lender[from], b.stage_borrower[from], b.stage_principal[from], b.stage_due[from],
                    b.stage_due_t[from]);
}

// model.loans.append(Loan(...)).
__device__ __forceinline__ void book_append(const Loans& b, unsigned int lender, unsigned int borrower, double principal,
                                            double due, int due_t) {
    if (book_put(b, *b.n, lender, borrower, principal, due, due_t)) ++*b.n;
}

// Python credit.on_death for the agent `ref`: its loans as borrower go (the lender's loss); each of its loans as lender
// is replaced, where it stood, by one loan per heir (principal / k, due / k, the same due period), the heirs being
// `heirs` (living children, in children order, the dying batch left out) without the loan's own borrower; with no heir
// left, or no heirs given (inheritance off), the loan is void. The new list is built in the staging list, then copied
// over the book, so a book at its capacity has room for it.
__device__ __forceinline__ void book_on_death(const Loans& b, unsigned int ref, const unsigned int* heirs,
                                              unsigned int n_heirs) {
    const unsigned int n = *b.n;
    unsigned int out = 0;
    for (unsigned int e = 0; e < n; ++e) {
        if (b.borrower[e] == ref) continue;
        if (b.lender[e] == ref) {
            unsigned int k = 0;
            for (unsigned int i = 0; i < n_heirs; ++i) k += heirs[i] != b.borrower[e] ? 1u : 0u;
            for (unsigned int i = 0; i < n_heirs && k; ++i) {
                if (heirs[i] == b.borrower[e]) continue;
                if (stage_put(b, out, heirs[i], b.borrower[e], b.principal[e] / k, b.due[e] / k, b.due_t[e])) ++out;
            }
            continue;
        }
        if (stage_put(b, out, b.lender[e], b.borrower[e], b.principal[e], b.due[e], b.due_t[e])) ++out;
    }
    for (unsigned int e = 0; e < out; ++e) book_from_stage(b, e, e);
    *b.n = out;
}

// Whether `ref` lends in the book (on_death has loans to pass on only then).
__device__ __forceinline__ bool book_lends(const Loans& b, unsigned int ref) {
    for (unsigned int e = 0; e < *b.n; ++e) {
        if (b.lender[e] == ref) return true;
    }
    return false;
}

#endif  // SRC_BOOK_CUH_
