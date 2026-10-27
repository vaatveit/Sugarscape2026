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

// model.loans.append(Loan(...)).
__device__ __forceinline__ void book_append(const Loans& b, unsigned int lender, unsigned int borrower, double principal,
                                            double due, int due_t) {
    if (book_put(b, *b.n, lender, borrower, principal, due, due_t)) ++*b.n;
}

// Python credit.on_death for the agent `ref`: its loans as borrower go (the lender's loss); each of its loans as lender
// is replaced, where it stood, by one loan per heir (principal / k, due / k, the same due period), the heirs being
// `heirs` (living children, in children order, the dying batch left out) without the loan's own borrower; with no heir
// left, or no heirs given (inheritance off), the loan is void. The new list is built past the old one's end, then moved
// down.
__device__ __forceinline__ void book_on_death(const Loans& b, unsigned int ref, const unsigned int* heirs,
                                              unsigned int n_heirs) {
    const unsigned int n = *b.n;
    unsigned int out = n;
    for (unsigned int e = 0; e < n; ++e) {
        if (b.borrower[e] == ref) continue;
        if (b.lender[e] == ref) {
            unsigned int k = 0;
            for (unsigned int i = 0; i < n_heirs; ++i) k += heirs[i] != b.borrower[e] ? 1u : 0u;
            for (unsigned int i = 0; i < n_heirs && k; ++i) {
                if (heirs[i] == b.borrower[e]) continue;
                if (book_put(b, out, heirs[i], b.borrower[e], b.principal[e] / k, b.due[e] / k, b.due_t[e])) ++out;
            }
            continue;
        }
        if (book_put(b, out, b.lender[e], b.borrower[e], b.principal[e], b.due[e], b.due_t[e])) ++out;
    }
    for (unsigned int e = n; e < out; ++e) book_put(b, e - n, b.lender[e], b.borrower[e], b.principal[e], b.due[e], b.due_t[e]);
    *b.n = out - n;
}

#endif  // SRC_BOOK_CUH_
