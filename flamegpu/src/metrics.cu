#include "metrics.h"

#include <algorithm>
#include <bitset>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <unordered_map>

namespace {

constexpr double NaN = std::numeric_limits<double>::quiet_NaN();

double ratio(double count, double total) { return total > 0 ? count / total : NaN; }

// Python's stats.gini: 2 * sum(rank_i * x_(i)) / (n * sum x) - (n + 1) / n over the sorted values.
double gini(std::vector<double> x) {
    const size_t n = x.size();
    double total = 0;
    for (const double v : x) total += v;
    if (n == 0 || total == 0) return NaN;
    std::sort(x.begin(), x.end());
    double ranked = 0;
    for (size_t i = 0; i < n; ++i) ranked += static_cast<double>(i + 1) * x[i];
    return 2.0 * ranked / (static_cast<double>(n) * total) - static_cast<double>(n + 1) / static_cast<double>(n);
}

int ones(uint64_t bits) { return static_cast<int>(std::bitset<64>(bits).count()); }

void put(FILE* f, double v) {
    if (std::isnan(v)) {
        std::fputs(",nan", f);
    } else {
        std::fprintf(f, ",%.17g", v);
    }
}

}  // namespace

const std::vector<std::string>& metric_names() {
    static const std::vector<std::string> names = {
        // standard_metrics
        "population", "mean_vision", "mean_metabolism", "mean_sugar", "gini", "mean_neighbors", "moved", "ne_fraction",
        "on_peak_fraction", "north_frac_high_vision", "north_frac_low_vision", "summer_north",
        // society_metrics
        "n_blue", "n_red", "blue_fraction", "sw_blue", "sw_red", "ne_blue", "ne_red", "blue_xy", "red_xy",
        "blue_advance", "red_advance", "mean_children", "best_friend_closeness", "friend_closeness", "agents_ever",
        // economic_metrics
        "mean_spice", "trades", "mean_price", "mean_log_price", "price_sd", "sugar_traded", "spice_traded",
        "mean_foresight", "n_loans", "n_lenders", "n_borrowers", "n_both", "credit_depth",
        // disease_metrics
        "mean_diseases", "sd_diseases", "fraction_sick", "new_infections", "diseases_circulating"};
    return names;
}

MetricsRow compute_metrics(const AgentColumns& a, const RunConfig& cfg, const std::vector<uint32_t>& capacity,
                           unsigned int t, unsigned int agents_ever) {
    const size_t n = a.x.size();
    const int half_w = cfg.width / 2, half_h = cfg.height / 2;
    double vision = 0, metabolism = 0, neighbors = 0, moved = 0, ne = 0, peak = 0;
    double high = 0, high_north = 0, low = 0, low_north = 0;
    std::vector<double> sugar(n);
    double sugar_sum = 0;
    for (size_t i = 0; i < n; ++i) {
        vision += a.vision[i];
        metabolism += a.metabolism[i];
        neighbors += a.neighbors[i];
        moved += a.moved[i];
        sugar[i] = a.sugar[i];  // + spice, which is 0 without the second commodity
        sugar_sum += sugar[i];
        const bool north = a.y[i] >= half_h;
        ne += (a.x[i] >= half_w && north) ? 1 : 0;
        peak += capacity[a.x[i] + static_cast<size_t>(a.y[i]) * cfg.width] >= 3 ? 1 : 0;
        if (a.vision[i] >= 5) {
            ++high;
            high_north += north ? 1 : 0;
        }
        if (a.vision[i] <= 2) {
            ++low;
            low_north += north ? 1 : 0;
        }
    }
    const double count = static_cast<double>(n);
    double summer_north = NaN;
    if (cfg.seasons) {
        const unsigned int gamma = static_cast<unsigned int>(cfg.seasons->second);
        summer_north = t % (2 * gamma) < gamma ? 1.0 : 0.0;
    }

    // society_metrics: tribes (p.73), the anti-diagonal's sides, genealogy (p.68), friends (p.79).
    const int L = cfg.tag_length;
    double n_blue = 0, n_red = 0, sw_blue = 0, sw_red = 0, blue_xy = 0, red_xy = 0, blue_adv = 0, red_adv = 0;
    double children = 0;
    std::unordered_map<uint32_t, size_t> by_uid;
    if (L) {
        for (size_t i = 0; i < n; ++i) by_uid[a.uid[i]] = i;
    }
    double best_sum = 0, mean_sum = 0, with_friends = 0;
    for (size_t i = 0; i < n; ++i) {
        children += a.n_children[i];
        if (!L) continue;
        const bool blue = 2 * ones(a.tags[i]) < L;
        const bool sw = a.x[i] + a.y[i] < cfg.width;
        (blue ? n_blue : n_red) += 1;
        (blue ? sw_blue : sw_red) += sw ? 1 : 0;
        (blue ? blue_xy : red_xy) += a.x[i] + a.y[i];
        (blue ? blue_adv : red_adv) += a.disp_x[i] + a.disp_y[i];
        double best = -1, total = 0, k = 0;
        for (uint32_t f = 0; f < a.n_friends[i]; ++f) {
            const auto it = by_uid.find(a.friend_uid[i * MAX_FRIENDS + f]);
            if (it == by_uid.end()) continue;  // dead
            const double closeness = 1.0 - static_cast<double>(ones(a.tags[i] ^ a.tags[it->second])) / L;
            best = std::max(best, closeness);
            total += closeness;
            ++k;
        }
        if (k > 0) {
            best_sum += best;
            mean_sum += total / k;
            ++with_friends;
        }
    }
    const double tagged = n_blue + n_red;
    const double any = n ? 0.0 : NaN;  // Python's safe_mean of a constant 0 per agent, nan for nobody
    return {t,
            {count, ratio(vision, count), ratio(metabolism, count), ratio(sugar_sum, count), gini(std::move(sugar)),
             ratio(neighbors, count), moved, ratio(ne, count), ratio(peak, count), ratio(high_north, high),
             ratio(low_north, low), summer_north,
             n_blue, n_red, ratio(n_blue, tagged), sw_blue, sw_red, n_blue - sw_blue, n_red - sw_red,
             ratio(blue_xy, n_blue), ratio(red_xy, n_red), ratio(blue_adv, n_blue), ratio(red_adv, n_red),
             n ? children / count : 0.0, ratio(best_sum, with_friends), ratio(mean_sum, with_friends),
             static_cast<double>(agents_ever),
             // economic_metrics without spice, trade or credit (Parts C and D fill them in).
             any, 0.0, NaN, NaN, NaN, 0.0, 0.0, any, 0.0, 0.0, 0.0, 0.0, 0.0,
             // disease_metrics without disease.
             any, any, any, 0.0, 0.0}};
}

CsvWriter::CsvWriter(const std::string& path) : file_(std::fopen(path.c_str(), "w")) {
    if (!file_) throw std::runtime_error("cannot write " + path);
    std::fputs("t", file_);
    for (const std::string& name : metric_names()) std::fprintf(file_, ",%s", name.c_str());
    std::fputc('\n', file_);
}

CsvWriter::~CsvWriter() {
    if (file_) std::fclose(file_);
}

void CsvWriter::write(const MetricsRow& r) {
    if (r.values.size() != metric_names().size()) throw std::logic_error("a metrics row with the wrong number of values");
    std::fprintf(file_, "%u", r.t);
    for (const double v : r.values) put(file_, v);
    std::fputc('\n', file_);
    std::fflush(file_);
}
