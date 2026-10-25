// Run configuration: the Phase 1 fields of the Python project's Config, read from run.cfg.
#ifndef SRC_CONFIG_H_
#define SRC_CONFIG_H_

#include <cstdint>
#include <optional>
#include <ostream>
#include <stdexcept>
#include <string>
#include <utility>

#ifndef SUGARSCAPE_MAX_CELLS
#define SUGARSCAPE_MAX_CELLS 6250000u
#endif

struct ConfigError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

struct IntRange {
    int lo, hi;
};

struct RunConfig {
    // World; width and height are the effective (tiled) size, tile the factor applied.
    int width = 50, height = 50;
    std::string map_path;
    int tile = 1;
    // Initial population.
    int initial_population = 400;
    std::string placement = "random";  // "random" | "block"
    int block[4] = {0, 0, 20, 20};  // x0, y0, w, h (repeated in every tile)
    // Genetics and endowment, inclusive ranges.
    IntRange vision{1, 6}, metabolism{1, 4}, endowment{5, 25};
    std::optional<IntRange> max_age;
    std::string founder_ages = "uniform";  // "uniform" | "zero"
    bool replacement = false;
    // Environment.
    double growback_rate = 1.0;  // INFINITY = G_inf
    std::optional<std::pair<int, int>> seasons;  // beta, gamma
    std::string winter_growback = "fractional";  // "fractional" | "pulse"
    std::optional<std::pair<double, double>> pollution;  // alpha, beta
    int pollution_start = 0;
    std::optional<int> pollution_stop;
    std::optional<int> diffusion_period;
    int diffusion_start = 0;
    int diffusion_passes = 1;  // passes of D per diffusion period (100 at xl, docs/xl.md)
    int look_stride = 1;       // one random look per stretch of this many sites; vision in whole strides (10 at xl)
    // Run.
    int steps = 0;
    uint64_t seed = 0;

    int base_width() const { return width / tile; }
    int base_height() const { return height / tile; }
    int64_t cells() const { return static_cast<int64_t>(width) * height; }
};

// Throws ConfigError naming the line and key for unknown, unsupported, duplicate or malformed entries.
RunConfig parse_config(const std::string& path);
// Tiles the world k x k: width, height and initial_population scale; the block repeats per tile.
void apply_tile(RunConfig& cfg, int k);
// The Python Config.__post_init__ rules for these fields, plus the compiled world-size limit.
void validate(const RunConfig& cfg);
// `key = value` lines in run.cfg spelling.
void print_config(std::ostream& out, const RunConfig& cfg);

#endif  // SRC_CONFIG_H_
