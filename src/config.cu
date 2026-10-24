#include "config.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <vector>

namespace {

// Python Config fields that Phase 1 does not implement (design: Non-goals).
const std::set<std::string> UNSUPPORTED = {
    "sugar_map", "sex", "fertility_start", "female_fertility_end", "male_fertility_end", "inheritance", "tag_length",
    "culture", "combat_alpha", "initial_blocks", "replacement_same_tribe", "fertility_threshold", "child_share",
    "mate_contact", "child_gift", "child_threshold", "gift_rounding", "spice", "spice_metabolism", "spice_endowment",
    "foresight", "cultural_preferences", "trade", "credit", "disease_list",
    "diseases_per_agent", "disease_length", "immune_length", "disease_fee"};

std::string trim(const std::string& s) {
    const auto b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos) return "";
    const auto e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

std::vector<std::string> split(const std::string& s, char sep) {
    std::vector<std::string> parts;
    std::stringstream ss(s);
    std::string part;
    while (std::getline(ss, part, sep)) parts.push_back(trim(part));
    return parts;
}

struct Entry {
    std::string value;
    int line;
};

class Reader {
 public:
    Reader(const std::string& path, std::map<std::string, Entry> entries) : path_(path), entries_(std::move(entries)) {}

    bool has(const std::string& key) const { return entries_.count(key) && !entries_.at(key).value.empty(); }
    bool present(const std::string& key) const { return entries_.count(key) > 0; }

    [[noreturn]] void fail(const std::string& key, const std::string& message) const {
        const auto it = entries_.find(key);
        const std::string where = it == entries_.end() ? path_ : path_ + " line " + std::to_string(it->second.line);
        throw ConfigError(where + ": " + key + ": " + message);
    }

    const std::string& raw(const std::string& key) const { return entries_.at(key).value; }

    long long integer(const std::string& key, const std::string& text) const {
        try {
            size_t used = 0;
            const long long v = std::stoll(text, &used);
            if (used == text.size()) return v;
        } catch (const std::exception&) {
        }
        fail(key, "expected an integer, got '" + text + "'");
    }

    double real(const std::string& key, const std::string& text) const {
        try {
            size_t used = 0;
            const double v = std::stod(text, &used);
            if (used == text.size() && std::isfinite(v)) return v;
        } catch (const std::exception&) {
        }
        fail(key, "expected a number, got '" + text + "'");
    }

    void get(const std::string& key, int& out) const {
        if (has(key)) out = static_cast<int>(integer(key, raw(key)));
    }
    void get(const std::string& key, uint64_t& out) const {
        if (has(key)) out = static_cast<uint64_t>(integer(key, raw(key)));
    }
    void get(const std::string& key, bool& out) const {
        if (!has(key)) return;
        if (raw(key) == "true") out = true;
        else if (raw(key) == "false") out = false;
        else fail(key, "expected true or false, got '" + raw(key) + "'");
    }
    void get(const std::string& key, std::string& out) const {
        if (has(key)) out = raw(key);
    }
    void get(const std::string& key, std::optional<int>& out) const {
        if (present(key)) out = has(key) ? std::optional<int>(static_cast<int>(integer(key, raw(key)))) : std::nullopt;
    }
    std::vector<long long> ints(const std::string& key, size_t n) const {
        const auto parts = split(raw(key), ',');
        if (parts.size() != n) fail(key, "expected " + std::to_string(n) + " comma-separated integers");
        std::vector<long long> v;
        for (const auto& p : parts) v.push_back(integer(key, p));
        return v;
    }
    void get(const std::string& key, IntRange& out) const {
        if (!has(key)) return;
        const auto v = ints(key, 2);
        out = {static_cast<int>(v[0]), static_cast<int>(v[1])};
    }
    void get(const std::string& key, std::optional<IntRange>& out) const {
        if (!present(key)) return;
        if (!has(key)) {
            out.reset();
            return;
        }
        const auto v = ints(key, 2);
        out = IntRange{static_cast<int>(v[0]), static_cast<int>(v[1])};
    }
    void get(const std::string& key, std::optional<std::pair<int, int>>& out) const {
        if (!present(key)) return;
        if (!has(key)) {
            out.reset();
            return;
        }
        const auto v = ints(key, 2);
        out = std::make_pair(static_cast<int>(v[0]), static_cast<int>(v[1]));
    }
    void get(const std::string& key, std::optional<std::pair<double, double>>& out) const {
        if (!present(key)) return;
        if (!has(key)) {
            out.reset();
            return;
        }
        const auto parts = split(raw(key), ',');
        if (parts.size() != 2) fail(key, "expected 2 comma-separated numbers");
        out = std::make_pair(real(key, parts[0]), real(key, parts[1]));
    }

 private:
    std::string path_;
    std::map<std::string, Entry> entries_;
};

const std::set<std::string> KNOWN = {
    "width", "height", "map", "initial_population", "placement", "block", "vision", "metabolism", "endowment",
    "max_age", "founder_ages", "replacement", "growback_rate", "seasons", "winter_growback", "pollution",
    "pollution_start", "pollution_stop", "diffusion_period", "diffusion_start", "steps", "seed"};

[[noreturn]] void invalid(const std::string& message) { throw ConfigError("invalid configuration: " + message); }

void check_range(const char* name, const IntRange& r) {
    if (r.lo > r.hi) invalid(std::string(name) + " range " + std::to_string(r.lo) + "," + std::to_string(r.hi) +
                             " has low > high");
}

std::string fmt(double v) {
    if (std::isinf(v)) return v > 0 ? "inf" : "-inf";
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.17g", v);
    return buf;
}

std::string fmt(const IntRange& r) { return std::to_string(r.lo) + "," + std::to_string(r.hi); }

}  // namespace

RunConfig parse_config(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw ConfigError(path + ": cannot open the configuration file");
    std::map<std::string, Entry> entries;
    std::string line;
    int number = 0;
    while (std::getline(in, line)) {
        ++number;
        const std::string text = trim(line);
        if (text.empty() || text[0] == '#') continue;
        const auto eq = text.find('=');
        const std::string where = path + " line " + std::to_string(number);
        if (eq == std::string::npos) throw ConfigError(where + ": expected 'key = value', got '" + text + "'");
        const std::string key = trim(text.substr(0, eq));
        if (UNSUPPORTED.count(key)) throw ConfigError(where + ": " + key + ": not supported in Phase 1 (Chapter II rules only)");
        if (!KNOWN.count(key)) throw ConfigError(where + ": " + key + ": unknown key");
        if (entries.count(key)) throw ConfigError(where + ": " + key + ": given twice");
        entries[key] = {trim(text.substr(eq + 1)), number};
    }
    const Reader r(path, entries);
    RunConfig cfg;
    for (const char* required : {"map", "steps"}) {
        if (!r.has(required)) r.fail(required, "is required");
    }
    r.get("width", cfg.width);
    r.get("height", cfg.height);
    r.get("map", cfg.map_path);
    r.get("initial_population", cfg.initial_population);
    r.get("placement", cfg.placement);
    if (r.has("block")) {
        const auto v = r.ints("block", 4);
        for (int i = 0; i < 4; ++i) cfg.block[i] = static_cast<int>(v[i]);
    }
    r.get("vision", cfg.vision);
    r.get("metabolism", cfg.metabolism);
    r.get("endowment", cfg.endowment);
    r.get("max_age", cfg.max_age);
    r.get("founder_ages", cfg.founder_ages);
    r.get("replacement", cfg.replacement);
    if (r.has("growback_rate")) {
        cfg.growback_rate = r.raw("growback_rate") == "inf" ? INFINITY : r.real("growback_rate", r.raw("growback_rate"));
    }
    r.get("seasons", cfg.seasons);
    r.get("winter_growback", cfg.winter_growback);
    r.get("pollution", cfg.pollution);
    r.get("pollution_start", cfg.pollution_start);
    r.get("pollution_stop", cfg.pollution_stop);
    r.get("diffusion_period", cfg.diffusion_period);
    r.get("diffusion_start", cfg.diffusion_start);
    r.get("steps", cfg.steps);
    r.get("seed", cfg.seed);
    return cfg;
}

void apply_tile(RunConfig& cfg, int k) {
    if (k < 1) invalid("--tile must be >= 1, not " + std::to_string(k));
    cfg.width *= k;
    cfg.height *= k;
    cfg.initial_population *= k * k;
    cfg.tile = k;
}

void validate(const RunConfig& cfg) {
    if (cfg.width < 1 || cfg.height < 1) invalid("width and height must be >= 1");
    if (cfg.cells() > static_cast<int64_t>(SUGARSCAPE_MAX_CELLS)) {
        invalid("a " + std::to_string(cfg.width) + "x" + std::to_string(cfg.height) + " world (" +
                std::to_string(cfg.cells()) + " sites) exceeds SUGARSCAPE_MAX_CELLS = " +
                std::to_string(SUGARSCAPE_MAX_CELLS) + "; rebuild with a larger -DSUGARSCAPE_MAX_CELLS");
    }
    check_range("vision", cfg.vision);
    check_range("metabolism", cfg.metabolism);
    check_range("endowment", cfg.endowment);
    if (cfg.max_age) check_range("max_age", *cfg.max_age);
    // Agents see only along the four lattice directions; opposite scans must not meet (Python Config).
    if (cfg.vision.hi * 2 >= std::min(cfg.base_width(), cfg.base_height())) {
        invalid("max vision " + std::to_string(cfg.vision.hi) + " must be less than half the grid (" +
                std::to_string(cfg.base_width()) + "x" + std::to_string(cfg.base_height()) + ")");
    }
    if (cfg.replacement && !cfg.max_age) invalid("replacement R[a,b] needs a max_age range [a, b]");
    if (cfg.founder_ages != "uniform" && cfg.founder_ages != "zero") {
        invalid("founder_ages must be uniform or zero, not '" + cfg.founder_ages + "'");
    }
    if (cfg.placement != "random" && cfg.placement != "block") {
        invalid("placement must be random or block, not '" + cfg.placement + "'");
    }
    if (cfg.winter_growback != "fractional" && cfg.winter_growback != "pulse") {
        invalid("winter_growback must be fractional or pulse, not '" + cfg.winter_growback + "'");
    }
    if (cfg.initial_population < 0) invalid("initial_population must be >= 0");
    if (cfg.growback_rate < 0) invalid("growback_rate must be >= 0");
    if (cfg.seasons && (cfg.seasons->first < 1 || cfg.seasons->second < 1)) invalid("seasons (beta, gamma) must both be >= 1");
    if (cfg.diffusion_period && *cfg.diffusion_period < 1) invalid("diffusion_period must be >= 1");
    if (cfg.pollution && (cfg.pollution->first < 0 || cfg.pollution->second < 0)) invalid("pollution coefficients must be >= 0");
    if (cfg.pollution_stop && *cfg.pollution_stop <= cfg.pollution_start) invalid("pollution_stop must come after pollution_start");
    if (cfg.steps < 1) invalid("steps must be >= 1");
    int64_t sites = cfg.cells();
    if (cfg.placement == "block") {
        const int w = cfg.block[2], h = cfg.block[3];
        if (!(1 <= w && w <= cfg.base_width() && 1 <= h && h <= cfg.base_height())) {
            invalid("block must have 1 <= w <= " + std::to_string(cfg.base_width()) + " and 1 <= h <= " +
                    std::to_string(cfg.base_height()));
        }
        sites = static_cast<int64_t>(w) * h * cfg.tile * cfg.tile;
    }
    if (cfg.initial_population > sites) {
        invalid(std::to_string(cfg.initial_population) + " agents do not fit in " + std::to_string(sites) + " " +
                cfg.placement + " sites");
    }
}

void print_config(std::ostream& out, const RunConfig& cfg) {
    auto opt_int = [](const std::optional<int>& v) { return v ? std::to_string(*v) : std::string(); };
    out << "width = " << cfg.width << "\n"
        << "height = " << cfg.height << "\n"
        << "map = " << cfg.map_path << "\n"
        << "tile = " << cfg.tile << "\n"
        << "initial_population = " << cfg.initial_population << "\n"
        << "placement = " << cfg.placement << "\n"
        << "block = " << cfg.block[0] << "," << cfg.block[1] << "," << cfg.block[2] << "," << cfg.block[3] << "\n"
        << "vision = " << fmt(cfg.vision) << "\n"
        << "metabolism = " << fmt(cfg.metabolism) << "\n"
        << "endowment = " << fmt(cfg.endowment) << "\n"
        << "max_age = " << (cfg.max_age ? fmt(*cfg.max_age) : "") << "\n"
        << "founder_ages = " << cfg.founder_ages << "\n"
        << "replacement = " << (cfg.replacement ? "true" : "false") << "\n"
        << "growback_rate = " << fmt(cfg.growback_rate) << "\n"
        << "seasons = " << (cfg.seasons ? std::to_string(cfg.seasons->first) + "," + std::to_string(cfg.seasons->second) : "") << "\n"
        << "winter_growback = " << cfg.winter_growback << "\n"
        << "pollution = " << (cfg.pollution ? fmt(cfg.pollution->first) + "," + fmt(cfg.pollution->second) : "") << "\n"
        << "pollution_start = " << cfg.pollution_start << "\n"
        << "pollution_stop = " << opt_int(cfg.pollution_stop) << "\n"
        << "diffusion_period = " << opt_int(cfg.diffusion_period) << "\n"
        << "diffusion_start = " << cfg.diffusion_start << "\n"
        << "steps = " << cfg.steps << "\n"
        << "seed = " << cfg.seed << "\n";
}
