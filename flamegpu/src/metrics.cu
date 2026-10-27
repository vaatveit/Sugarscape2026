#include "metrics.h"

#include <algorithm>
#include <bitset>
#include <cmath>
#include <limits>
#include <map>
#include <set>
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

// Python's _longest_chain: the longest lender -> borrower path, in loans, through the credit network; simple paths only.
using Edges = std::map<uint32_t, std::set<uint32_t>>;
int walk(const Edges& edges, uint32_t node, std::set<uint32_t>& on_path) {
    int best = 0;
    const auto it = edges.find(node);
    if (it == edges.end()) return 0;
    for (const uint32_t next : it->second) {
        if (on_path.count(next)) continue;
        on_path.insert(next);
        best = std::max(best, 1 + walk(edges, next, on_path));
        on_path.erase(next);
    }
    return best;
}

int longest_chain(const Edges& edges) {
    int best = 0;
    for (const auto& [node, _] : edges) {
        std::set<uint32_t> on_path{node};
        best = std::max(best, walk(edges, node, on_path));
    }
    return best;
}

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
                           unsigned int t, unsigned int agents_ever, const TradeTotals& trade,
                           const std::vector<LoanRecord>& loans) {
    const size_t n = a.x.size();
    const int half_w = cfg.width / 2, half_h = cfg.height / 2;
    double vision = 0, metabolism = 0, neighbors = 0, moved = 0, ne = 0, peak = 0, spice = 0, foresight = 0;
    double high = 0, high_north = 0, low = 0, low_north = 0;
    std::vector<double> sugar(n);
    double sugar_sum = 0;
    for (size_t i = 0; i < n; ++i) {
        vision += a.vision[i];
        metabolism += a.metabolism[i];
        neighbors += a.neighbors[i];
        moved += a.moved[i];
        sugar_sum += a.sugar[i];
        sugar[i] = a.sugar[i] + a.spice[i];  // gini's wealth: spice is 0 without the second commodity
        spice += a.spice[i];
        foresight += a.foresight[i];
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
    // economic_metrics' credit network (p.133): loans, lenders, borrowers, those that are both, and the longest chain.
    std::set<uint32_t> lenders, borrowers;
    Edges edges;
    for (const LoanRecord& l : loans) {
        lenders.insert(l.lender);
        borrowers.insert(l.borrower);
        edges[l.lender].insert(l.borrower);
    }
    double both = 0;
    for (const uint32_t u : lenders) both += borrowers.count(u) ? 1 : 0;

    // disease_metrics (p.147): the diseases each agent carries (np.std is the population's), the share sick, and the
    // distinct strings carried, which canonical ids count once each. Without disease every count is 0.
    double diseases = 0, sick = 0;
    for (size_t i = 0; i < n; ++i) {
        diseases += a.n_diseases[i];
        sick += a.n_diseases[i] > 0 ? 1 : 0;
    }
    const double mean_diseases = ratio(diseases, count);
    double squares = 0;
    for (size_t i = 0; i < n; ++i) squares += (a.n_diseases[i] - mean_diseases) * (a.n_diseases[i] - mean_diseases);
    std::set<uint8_t> circulating;
    if (cfg.disease()) {
        for (size_t i = 0; i < n; ++i) {
            for (uint32_t k = 0; k < a.n_diseases[i]; ++k) circulating.insert(a.diseases[i * MAX_DISEASES + k]);
        }
    }

    const double tagged = n_blue + n_red;
    return {t,
            {count, ratio(vision, count), ratio(metabolism, count), ratio(sugar_sum, count), gini(std::move(sugar)),
             ratio(neighbors, count), moved, ratio(ne, count), ratio(peak, count), ratio(high_north, high),
             ratio(low_north, low), summer_north,
             n_blue, n_red, ratio(n_blue, tagged), sw_blue, sw_red, n_blue - sw_blue, n_red - sw_red,
             ratio(blue_xy, n_blue), ratio(red_xy, n_red), ratio(blue_adv, n_blue), ratio(red_adv, n_red),
             n ? children / count : 0.0, ratio(best_sum, with_friends), ratio(mean_sum, with_friends),
             static_cast<double>(agents_ever),
             // economic_metrics: mean_spice and mean_foresight (0 without spice); the period's trades (fn 25: the
             // geometric mean price; np.std of ln p); the credit network.
             ratio(spice, count), trade.n, trade.n > 0 ? std::exp(trade.mean) : NaN, trade.n > 0 ? trade.mean : NaN,
             trade.n > 0 ? std::sqrt(trade.m2 / trade.n) : NaN, trade.sugar, trade.spice, ratio(foresight, count),
             static_cast<double>(loans.size()), static_cast<double>(lenders.size()),
             static_cast<double>(borrowers.size()), both, static_cast<double>(longest_chain(edges)),
             // disease_metrics; new infections come with rule E (Task 3 of plan 2026-10-27-gpu-parity-part-d).
             mean_diseases, n ? std::sqrt(squares / count) : NaN, ratio(sick, count), 0.0,
             static_cast<double>(circulating.size())}};
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
