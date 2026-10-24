// sugarscape_gpu: the Chapter II Sugarscape rules on FLAME GPU 2.
// Design: docs/superpowers/specs/2026-10-23-phase1-chapter2-gpu-design.md

#include <cstdio>
#include <cstdlib>
#include <string>

#include "flamegpu/flamegpu.h"

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

int usage_error(const std::string& message) {
    std::fprintf(stderr, "sugarscape_gpu: %s\n\n%s", message.c_str(), USAGE);
    return 2;
}

}  // namespace

int main(int argc, const char** argv) {
    if (argc < 2) {
        return usage_error("--config is required");
    }
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--help") {
            std::fputs(USAGE, stdout);
            return EXIT_SUCCESS;
        }
        return usage_error("unknown option " + arg);
    }
    return EXIT_SUCCESS;
}
