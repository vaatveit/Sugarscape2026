// sugarscape_gpu: the Chapter II Sugarscape rules on FLAME GPU 2.
// Design: docs/superpowers/specs/2026-10-23-phase1-chapter2-gpu-design.md

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <numeric>
#include <optional>
#include <string>

#include "flamegpu/flamegpu.h"

#include "config.h"
#include "host_state.h"
#include "landscape_io.h"
#include "model.h"

namespace {

const char* const USAGE =
    "Usage: sugarscape_gpu --config run.cfg [options]\n"
    "\n"
    "  --config FILE          run configuration (key = value lines)\n"
    "  --out FILE             per-period metrics CSV\n"
    "  --init FILE            starting agents CSV (x,y,vision,metabolism,sugar,age,max_age)\n"
    "  --metrics-every N      write the metrics row only when t % N == 0 (default 1)\n"
    "  --dump-agents FILE     agents CSV at period --dump-at\n"
    "  --dump-landscape FILE  landscape CSV at period --dump-at\n"
    "  --dump-at T            period of the dumps (0 = after initialisation)\n"
    "  --tile K               tile the map K x K (population x K^2)\n"
    "  --timing FILE          timing JSON\n"
    "  --check                check invariants every period (exit 3 on a violation)\n"
    "  --print-config         print the effective configuration and exit\n"
    "  --version              print the FLAME GPU, CUDA and GPU versions and the build's settings, and exit\n"
    "  --help                 this text\n";

struct UsageError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

struct Options {
    std::string config, out, init, dump_agents, dump_landscape, timing;
    int metrics_every = 1;
    std::optional<int> dump_at;
    int tile = 1;
    bool check = false;
    bool print_config = false;
    bool help = false;
    bool version = false;
};

// The machine and build facts a timing is read against (the bridge's machine.txt), as key = value lines.
void print_version() {
    int runtime = 0;
    cudaRuntimeGetVersion(&runtime);
    cudaDeviceProp device{};
    const bool have_device = cudaGetDeviceProperties(&device, 0) == cudaSuccess;
#if !defined(FLAMEGPU_SEATBELTS) || FLAMEGPU_SEATBELTS  // as FLAME GPU itself tests it
    const char* seatbelts = "on";
#else
    const char* seatbelts = "off";
#endif
    std::printf("flamegpu = %s\ncuda_runtime = %d.%d\ngpu = %s\nseatbelts = %s\nmax_cells = %u\n", flamegpu::VERSION_FULL,
                runtime / 1000, runtime % 1000 / 10, have_device ? device.name : "none", seatbelts,
                static_cast<unsigned int>(SUGARSCAPE_MAX_CELLS));
    // Flush now: CUDA, started above, can end the process at exit before stdout is flushed (the output was lost
    // in about 1 run in 4, with exit code 0).
    std::fflush(stdout);
}

int to_int(const std::string& option, const std::string& text) {
    try {
        size_t used = 0;
        const int v = std::stoi(text, &used);
        if (used == text.size()) return v;
    } catch (const std::exception&) {
    }
    throw UsageError(option + " expects an integer, got '" + text + "'");
}

Options parse_args(int argc, const char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        auto value = [&]() -> std::string {
            if (i + 1 >= argc) throw UsageError(arg + " needs a value");
            return argv[++i];
        };
        if (arg == "--help") o.help = true;
        else if (arg == "--version") o.version = true;
        else if (arg == "--check") o.check = true;
        else if (arg == "--print-config") o.print_config = true;
        else if (arg == "--config") o.config = value();
        else if (arg == "--out") o.out = value();
        else if (arg == "--init") o.init = value();
        else if (arg == "--dump-agents") o.dump_agents = value();
        else if (arg == "--dump-landscape") o.dump_landscape = value();
        else if (arg == "--timing") o.timing = value();
        else if (arg == "--metrics-every") o.metrics_every = to_int(arg, value());
        else if (arg == "--dump-at") o.dump_at = to_int(arg, value());
        else if (arg == "--tile") o.tile = to_int(arg, value());
        else throw UsageError("unknown option " + arg);
    }
    if (o.help || o.version) return o;
    if (o.config.empty()) throw UsageError("--config is required");
    if (o.metrics_every < 1) throw UsageError("--metrics-every must be >= 1");
    if ((!o.dump_agents.empty() || !o.dump_landscape.empty()) && !o.dump_at) {
        throw UsageError("--dump-agents/--dump-landscape need --dump-at");
    }
    return o;
}

}  // namespace

int main(int argc, const char** argv) {
    Options opts;
    try {
        opts = parse_args(argc, argv);
    } catch (const UsageError& e) {
        std::fprintf(stderr, "sugarscape_gpu: %s\n\n%s", e.what(), USAGE);
        return 2;
    }
    if (opts.help) {
        std::fputs(USAGE, stdout);
        return EXIT_SUCCESS;
    }
    if (opts.version) {
        print_version();
        return EXIT_SUCCESS;
    }
    RunConfig cfg;
    std::vector<uint32_t> capacity;
    // docs/xl.md's setup: from loading the map to the state at t = 0 (finish_init's setup_end).
    std::chrono::steady_clock::time_point setup_start;
    try {
        cfg = parse_config(opts.config);
        apply_tile(cfg, opts.tile);
        validate(cfg);
        setup_start = std::chrono::steady_clock::now();
        capacity = tile_map(load_map(cfg.map_path, cfg.base_width(), cfg.base_height()), cfg.base_width(),
                            cfg.base_height(), cfg.tile);
    } catch (const std::runtime_error& e) {  // ConfigError, MapError
        std::fprintf(stderr, "sugarscape_gpu: %s\n", e.what());
        return 2;
    }
    if (opts.print_config) {
        print_config(std::cout, cfg);
        std::cout << "map_cells = " << capacity.size() << "\n"
                  << "map_capacity_sum = " << std::accumulate(capacity.begin(), capacity.end(), uint64_t{0}) << "\n";
        return EXIT_SUCCESS;
    }
    std::vector<InitAgent> init;
    try {
        if (!opts.init.empty()) init = load_init_agents(opts.init, cfg.width, cfg.height);
    } catch (const std::runtime_error& e) {
        std::fprintf(stderr, "sugarscape_gpu: %s\n", e.what());
        return 2;
    }

    RunState& s = state();
    s.cfg = cfg;
    s.capacity = std::move(capacity);
    s.rng.seed(cfg.seed);
    s.dump_agents = opts.dump_agents;
    s.dump_landscape = opts.dump_landscape;
    if (opts.dump_at) s.dump_at = static_cast<unsigned int>(*opts.dump_at);
    s.check = opts.check;
    s.metrics_every = static_cast<unsigned int>(opts.metrics_every);
    s.timing = !opts.timing.empty();
    try {
        if (!opts.out.empty()) s.csv = std::make_unique<CsvWriter>(opts.out);
    } catch (const std::runtime_error& e) {
        std::fprintf(stderr, "sugarscape_gpu: %s\n", e.what());
        return 2;
    }

    try {
        flamegpu::io::Telemetry::suppressNotice();  // telemetry is off (design: Constraints)
        flamegpu::ModelDescription model("sugarscape");
        describe_model(model, cfg);
        flamegpu::CUDASimulation simulation(model);
        simulation.SimulationConfig().random_seed = cfg.seed;
        simulation.SimulationConfig().steps = static_cast<unsigned int>(cfg.steps);
        simulation.SimulationConfig().verbosity = flamegpu::Verbosity::Quiet;
        simulation.SimulationConfig().telemetry = false;
        simulation.applyConfig();
        flamegpu::AgentVector citizens = make_citizens(model, opts.init.empty() ? nullptr : &init);
        flamegpu::AgentVector cells = make_cells(model);
        simulation.setPopulationData(citizens);
        simulation.setPopulationData(cells);
        const auto start = std::chrono::steady_clock::now();
        simulation.simulate();
        const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        if (!opts.timing.empty()) {
            // Periods timed by begin_period/end_period with the GPU synchronised, leaving out initialisation and the
            // metrics. FLAME GPU's own step timer stops before the kernels finish when seatbelts are off.
            const std::vector<double>& steps = s.period_seconds;
            double step_total = 0;
            for (const double v : steps) step_total += v;
            const double setup = std::chrono::duration<double>(s.setup_end - setup_start).count();
            FILE* f = std::fopen(opts.timing.c_str(), "w");
            if (!f) throw std::runtime_error("cannot write " + opts.timing);
            // The first five keys are bridge.bench's; the rest are docs/xl.md's timing measures.
            std::fprintf(f,
                         "{\"cells\": %lld, \"agents_initial\": %u, \"steps\": %d, \"simulate_seconds\": %.9g, "
                         "\"step_seconds_mean\": %.9g, \"setup_s\": %.9g, \"stepping_s\": %.9g, \"metrics_s\": %.9g, "
                         "\"periods\": %zu, \"agents_start\": %u, \"agents_end\": %u}\n",
                         static_cast<long long>(cfg.cells()), citizens.size(), cfg.steps, seconds,
                         steps.empty() ? 0.0 : step_total / static_cast<double>(steps.size()), setup, step_total,
                         s.metrics_seconds, steps.size(), citizens.size(), s.population);
            std::fclose(f);
        }
    } catch (const InvariantError& e) {
        std::fprintf(stderr, "sugarscape_gpu: invariant violated: %s\n", e.what());
        return 3;
    } catch (const RoundLimitError& e) {
        std::fprintf(stderr, "sugarscape_gpu: %s\n", e.what());
        return 4;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "sugarscape_gpu: %s\n", e.what());
        return 1;
    }
    flamegpu::util::cleanup();
    return EXIT_SUCCESS;
}
