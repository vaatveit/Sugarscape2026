// Run configuration: the Phase 1 fields of the Python project's Config, read from run.cfg.
#ifndef SRC_CONFIG_H_
#define SRC_CONFIG_H_

#include <cstdint>
#include <optional>
#include <ostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#ifndef SUGARSCAPE_MAX_CELLS
#define SUGARSCAPE_MAX_CELLS 6250000u
#endif

struct ConfigError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

struct IntRange {
    int lo, hi;
};

// The most cultural tag bits a citizen holds (one uint64_t; spec 2026-10-25-gpu-full-parity, section 5).
constexpr int MAX_TAG_BITS = 63;
// Networks of friends (p.79): each citizen remembers at most this many.
constexpr unsigned int MAX_FRIENDS = 5;
// Rule S with partners in sight: the most looks along each line, vision / look_stride (24 registered).
constexpr int MAX_SIGHT_LOOKS = 64;

// One tribal starting block of Python's Config.initial_blocks: n agents of the tribe in the w x h block at x0, y0.
struct TribeBlock {
    std::string tribe;  // "blue" | "red"
    int x0, y0, w, h, n;
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
    int look_stride = 1;       // one random look per whole stride of vision, centred on it; vision in whole strides (10 at xl)
    // Chapter III without combat (spec 2026-10-25-gpu-full-parity, Part A), Python's defaults.
    bool sex = false;                                       // rule S (p.56)
    IntRange fertility_start{12, 15};                       // p.57, both sexes
    IntRange female_fertility_end{40, 50}, male_fertility_end{50, 60};
    bool inheritance = false;                               // rule I (p.67)
    int tag_length = 0;                                     // 0 = no cultural tags
    bool culture = false;                                   // rule K and friends (p.73)
    std::vector<TribeBlock> initial_blocks;                 // non-empty replaces placement and initial_population
    double fertility_threshold = 1.0, child_share = 0.5;    // p.55
    std::string mate_contact = "vision";                    // "vision" | "neighbors"
    std::string child_gift = "endowment";                   // "endowment" | "capped"
    std::string child_threshold = "endowment";              // "endowment" | "redraw"
    std::string gift_rounding = "down";                     // "down" | "exact"
    // Combat and same-tribe replacement (spec 2026-10-25-gpu-full-parity, Part B).
    std::optional<double> combat_alpha;                     // rule C_alpha (p.83); INFINITY = C_inf; none = movement M
    bool replacement_same_tribe = false;                    // R with newcomers of the dead agent's tribe (p.86)
    // Chapter IV (spec 2026-10-25-gpu-full-parity, Part C), Python's defaults.
    bool spice = false;                                     // the second commodity (p.96); the sugar map mirrored
    IntRange spice_metabolism{1, 5};                        // p.108
    std::optional<IntRange> spice_endowment;                // none: endowment's range
    std::optional<IntRange> foresight;                      // phi (p.129); none: myopic, phi = 0
    bool cultural_preferences = false;                      // eq. 5 (p.124)
    bool trade = false;                                     // rule T (p.105)
    std::string trade_rounding = "exact";                   // "exact" | "down" (VAR-inttrade)
    std::optional<std::pair<int, double>> credit;           // L_dr (p.132): duration d, rate r percent
    // Run.
    int steps = 0;
    uint64_t seed = 0;
    // Command-line options, not run.cfg keys (spec 2026-10-25-gpu-full-parity, section 2).
    bool force_turns = false;              // --force-turns: the turns even without an interaction rule (tests)
    bool serial_turns = false;             // --serial-turns: one turn per wave, in the period's order
    unsigned int uid_capacity = 1u << 24;  // --uid-capacity: the most agents a run may create

    // Whether every turn after movement runs in the ordered turns (spec section 1).
    // Inheritance counts: its old-age layers live on the turns path, and a run may give children through --init.
    bool turns_on() const { return sex || culture || combat() || inheritance || trade || credit || force_turns; }
    bool combat() const { return combat_alpha.has_value(); }
    // One turn per wave: --serial-turns, or inheritance with combat, credit or spice, whose deaths in a turn have heirs
    // (and with credit, loans passed on) found only at the death, so they cannot be in a footprint (spec section 2;
    // plan 2026-10-26-gpu-parity-part-c, ruling R1).
    bool serial() const { return serial_turns || (inheritance && (combat() || credit || spice)); }

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
