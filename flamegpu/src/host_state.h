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

struct InvariantError : std::runtime_error {  // --check found a violation: exit 3
    using std::runtime_error::runtime_error;
};
struct RoundLimitError : std::runtime_error {  // movement needed more rounds than the claim key holds: exit 4
    using std::runtime_error::runtime_error;
};

struct RunState {
    RunConfig cfg;
    std::vector<uint32_t> capacity;  // indexed x + y * width
    std::mt19937_64 rng;             // host-side draws: placement, replacement
    unsigned int population = 0;     // citizens at the end of the last completed period
    unsigned int births = 0;         // replacements created this period
    // Output options.
    std::string dump_agents, dump_landscape;
    std::optional<unsigned int> dump_at;
    bool check = false;
    std::unique_ptr<CsvWriter> csv;  // --out
    unsigned int metrics_every = 1;
    // --timing: wall-clock seconds of setup, of each period (the GPU synchronised at both ends), and of the metrics.
    bool timing = false;
    std::chrono::steady_clock::time_point setup_end;  // the t = 0 state reached, before its outputs (finish_init)
    std::chrono::steady_clock::time_point period_start;
    std::vector<double> period_seconds;
    double metrics_seconds = 0;  // gathering each metrics row, t = 0 included (the CSV write left out)
};

RunState& state();

// The initial citizens: the --init agents if given, else drawn as the spec's Initialisation section says.
flamegpu::AgentVector make_citizens(flamegpu::ModelDescription& model, const std::vector<InitAgent>* init);
// One cell agent per site, carrying the site's capacity.
flamegpu::AgentVector make_cells(flamegpu::ModelDescription& model);

// Dumps for --dump-at and the --check invariants, for the period that has just completed (t = 0 after init).
void write_dumps(flamegpu::HostAPI* api, unsigned int t);
// The metrics row for period t, when --out is given and t % --metrics-every == 0.
void write_metrics(flamegpu::HostAPI* api, unsigned int t);
void check_invariants(flamegpu::HostAPI* api, unsigned int t, unsigned int deaths, unsigned int births);

FLAMEGPU_HOST_FUNCTION_DECL(begin_period)    // layer: t, round and the period's rule switches
FLAMEGPU_HOST_FUNCTION_DECL(finish_init)     // layer, first period only: the t = 0 outputs
FLAMEGPU_HOST_FUNCTION_DECL(replace_dead)    // layer: replacement R
FLAMEGPU_HOST_FUNCTION_DECL(end_period)      // step: deaths, dumps, checks

#endif  // SRC_HOST_STATE_H_
