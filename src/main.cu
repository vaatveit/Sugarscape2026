// sugarscape_gpu: the Chapter II Sugarscape rules on FLAME GPU 2.
// Design: docs/superpowers/specs/2026-10-23-phase1-chapter2-gpu-design.md

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <numeric>
#include <optional>
#include <string>

#include "flamegpu/flamegpu.h"

#include "config.h"
#include "landscape_io.h"

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
};

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
    if (o.help) return o;
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
    RunConfig cfg;
    std::vector<uint32_t> capacity;
    try {
        cfg = parse_config(opts.config);
        apply_tile(cfg, opts.tile);
        validate(cfg);
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
    return EXIT_SUCCESS;
}
