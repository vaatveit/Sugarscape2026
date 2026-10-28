// State shared by the host functions of one run, the populations, and the run's error types.
#ifndef SRC_HOST_STATE_H_
#define SRC_HOST_STATE_H_

#include <chrono>
#include <cstdint>
#include <memory>
#include <optional>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "flamegpu/flamegpu.h"

#include "config.h"
#include "landscape_io.h"
#include "metrics.h"
#include "store.h"

struct InvariantError : std::runtime_error {  // --check found a violation: exit 3
    using std::runtime_error::runtime_error;
};
struct RoundLimitError : std::runtime_error {  // movement needed more rounds than the claim key holds: exit 4
    using std::runtime_error::runtime_error;
};

struct RunState {
    RunConfig cfg;
    std::vector<uint32_t> capacity;  // indexed x + y * width
    std::vector<uint32_t> spice_capacity;  // the sugar map mirrored east-west with spice on, else 0 (make_cells)
    std::mt19937_64 rng;             // host-side draws: the founders (replacement draws on the device)
    unsigned int population = 0;     // citizens at the end of the last completed period
    unsigned int next_uid = 0;       // the founders' count: the first uid the device hands out
    unsigned int agents_ever = 0;    // every agent created so far (Python's Model.agents_ever), after each period
    // The turns (spec 2026-10-25-gpu-full-parity, section 2) and R's newcomers' uids.
    std::unique_ptr<StoreHost> store;
    std::unique_ptr<NewcomerUids> newcomers;
    std::unique_ptr<DyingTable> dying;
    std::unique_ptr<LoanBook> loans;  // rule L's book (loans.h)
    std::string dump_loans;           // --dump-loans: the book at --dump-at
    unsigned int turn_rows = 0;          // citizens taking turns this period
    unsigned int waves_this_period = 0;
    unsigned int newborns_this_period = 0;  // rule S's children, for --check's population count
    std::vector<unsigned int> waves;     // per completed period, for --timing's waves_mean
    TradeTotals trades;                  // the last period's exchanges (turns.cuh, total_trades)
    unsigned int new_infections = 0;     // the last period's (turns.cuh, total_infections)
    // Chapter V's master list (p.147; make_disease_list): each disease's bits (bit i is Python's element i) and length,
    // and its canonical id, the lowest index with the same string, which agents carry.
    std::vector<uint64_t> disease_bits;
    std::vector<unsigned int> disease_len, disease_canon;
    // Output options.
    std::string dump_agents, dump_landscape;
    std::string dump_order;  // --dump-order: each period's uids in turn order (record_order; tests)
    FILE* order_file = nullptr;
    std::optional<unsigned int> dump_at;
    bool check = false;
    std::unique_ptr<CsvWriter> csv;  // --out
    unsigned int metrics_every = 1;
    // --timing: wall-clock seconds of setup, of each period (the GPU synchronised at both ends), and of the metrics.
    bool timing = false;
    std::chrono::steady_clock::time_point setup_end;  // the t = 0 state reached, before its outputs (finish_init)
    std::chrono::steady_clock::time_point period_start;
    std::vector<double> period_seconds;
    double metrics_seconds = 0;  // gathering each metrics row, t = 0 included (the CSV write left out; write_metrics)
};

RunState& state();

// Chapter V's master list, with disease on: drawn first of all the host's draws, as Python's Model.__init__ draws it,
// or read from --disease-list (path, one 0/1 string per line, bit 0 first; MapError naming the file); then each
// entry's canonical id. With --dump-diseases (dump, non-empty) writes index,canonical,bits per entry.
void make_disease_list(const std::string& path, const std::string& dump);
// The --init agents' diseases as canonical ids (ruling D2): MapError naming the line for two indices of one string.
void canonical_init_diseases(const std::string& path, std::vector<InitAgent>& agents);
// The initial citizens: the --init agents if given, else drawn as the spec's Initialisation section says.
flamegpu::AgentVector make_citizens(flamegpu::ModelDescription& model, const std::vector<InitAgent>* init);
// One cell agent per site, carrying the site's capacity.
flamegpu::AgentVector make_cells(flamegpu::ModelDescription& model);

// Dumps for --dump-at and the --check invariants, for the period that has just completed (t = 0 after init).
void write_dumps(flamegpu::HostAPI* api, unsigned int t);
// The metrics row for period t, when --out is given and t % --metrics-every == 0. Run by main between steps: with
// a simulation, citizens is first refreshed from the device; with nullptr (t = 0) it is read as given, the founders.
void write_metrics(flamegpu::CUDASimulation* simulation, flamegpu::AgentVector& citizens, unsigned int t);
void check_invariants(flamegpu::HostAPI* api, unsigned int t, unsigned int deaths, unsigned int births);

FLAMEGPU_HOST_FUNCTION_DECL(begin_period)    // layer: t, round and the period's rule switches
FLAMEGPU_HOST_FUNCTION_DECL(finish_init)     // layer, first period only: the t = 0 dumps and checks
FLAMEGPU_HOST_FUNCTION_DECL(end_period)      // step: deaths, dumps, checks
FLAMEGPU_HOST_FUNCTION_DECL(record_order)    // layer after start_period, with --dump-order only: the period's order

#endif  // SRC_HOST_STATE_H_
