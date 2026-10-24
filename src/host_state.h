// State shared by the host functions of one run, the populations, and the run's error types.
#ifndef SRC_HOST_STATE_H_
#define SRC_HOST_STATE_H_

#include <cstdint>
#include <optional>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "flamegpu/flamegpu.h"

#include "config.h"
#include "landscape_io.h"

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
    std::vector<uint32_t> initial_sites;
    unsigned int population = 0;     // citizens at the end of the last completed period
    // Output options.
    std::string dump_agents, dump_landscape;
    std::optional<unsigned int> dump_at;
    bool check = false;
};

RunState& state();

// The initial citizens: the --init agents if given, else drawn as the spec's Initialisation section says.
flamegpu::AgentVector make_citizens(flamegpu::ModelDescription& model, const std::vector<InitAgent>* init);
// One cell agent per site.
flamegpu::AgentVector make_cells(flamegpu::ModelDescription& model);

// Dumps for --dump-at and the --check invariants, for the period that has just completed (t = 0 after init).
void write_dumps(flamegpu::HostAPI* api, unsigned int t);
void check_invariants(flamegpu::HostAPI* api, unsigned int t, unsigned int deaths, unsigned int births);

FLAMEGPU_HOST_FUNCTION_DECL(init_landscape)  // init: capacity, sugar, occupied; t = 0 outputs
FLAMEGPU_HOST_FUNCTION_DECL(begin_period)    // layer: t, round and the period's rule switches
FLAMEGPU_HOST_FUNCTION_DECL(end_period)      // step: deaths, dumps, checks

#endif  // SRC_HOST_STATE_H_
