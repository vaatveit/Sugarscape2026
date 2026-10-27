// Credit L's loan book on the device, in Python's list order (sugarscape.rules.credit, pp.131-133; plan
// 2026-10-26-gpu-parity-part-c, Tasks 6 and 7). The turns read it and add loans in their rows; one device thread rebuilds
// it after the turns, and runs the end of the period: old-age deaths' on_death, then settle_loans.
#ifndef SRC_LOANS_H_
#define SRC_LOANS_H_

#include <cstdint>
#include <vector>

// Python's credit.Loan: lender and borrower are uids, in list order. The device copy is part of the Store.
struct Loans {
    unsigned int capacity;  // 2 x cells (exit 5 beyond it)
    unsigned int* n;        // loans in the book
    unsigned int *lender, *borrower;
    double *principal, *due;
    int* due_t;
    int *lender_row, *borrower_row;  // this period's rows (LoanBook::index, at schedule)
    double* ledger_sugar;            // the end of the period: each citizen's sugar by its index (ledger_post)
    unsigned int* errors;            // LOAN_CAPACITY_ERROR
};

constexpr unsigned int LOANS_PER_CELL = 2;
constexpr unsigned int LOAN_SLOTS = 4;  // a turn's new loans: one per neighbour at most
constexpr unsigned int LOAN_CAPACITY_ERROR = 1u;

struct LoanRecord {
    uint32_t lender, borrower;
    double principal, due;
    int due_t;
};

struct Store;
struct Dying;

class LoanBook {
 public:
    LoanBook(unsigned int cells, unsigned int rows);
    ~LoanBook();
    LoanBook(const LoanBook&) = delete;
    LoanBook& operator=(const LoanBook&) = delete;
    const Loans& device() const { return h_; }
    // The book in list order, for metrics and --dump-loans.
    std::vector<LoanRecord> to_host() const;
    // Throws CapacityError when the book overflowed.
    void check_errors() const;

 private:
    Loans h_{};
};

// At schedule, after publish: each loan's lender and borrower rows, and each row's start-of-period loans as borrower
// in list order (s.loan_first, s.loan_count, s.loan_entry).
void loan_index(const Store& s);
// After the turns and birth_uids, without inheritance: loans with a dead party go, and each row's new loans are
// appended, rows in rank order (Python appends them at the borrower's turn), due at due_t = t + d.
void rebuild_loans(const Store& s, int due_t);
// The end of the period: on_death for the dying (old age, uid order; with inheritance their loans pass to their heirs),
// then settle_loans(t), on ledger_sugar.
void run_ledger(const Store& s, const Dying& d, int t, int duration, double rate, bool inheritance);

#endif  // SRC_LOANS_H_
