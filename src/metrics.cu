#include "metrics.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

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

void put(FILE* f, double v) {
    if (std::isnan(v)) {
        std::fputs(",nan", f);
    } else {
        std::fprintf(f, ",%.17g", v);
    }
}

}  // namespace

MetricsRow compute_metrics(const AgentColumns& a, const RunConfig& cfg, const std::vector<uint32_t>& capacity,
                           unsigned int t) {
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
        sugar[i] = a.sugar[i];
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
    return {t,
            count,
            ratio(vision, count),
            ratio(metabolism, count),
            ratio(sugar_sum, count),
            gini(std::move(sugar)),
            ratio(neighbors, count),
            moved,
            ratio(ne, count),
            ratio(peak, count),
            ratio(high_north, high),
            ratio(low_north, low),
            summer_north};
}

CsvWriter::CsvWriter(const std::string& path) : file_(std::fopen(path.c_str(), "w")) {
    if (!file_) throw std::runtime_error("cannot write " + path);
    std::fputs("t,population,mean_vision,mean_metabolism,mean_sugar,gini,mean_neighbors,moved,ne_fraction,"
               "on_peak_fraction,north_frac_high_vision,north_frac_low_vision,summer_north\n", file_);
}

CsvWriter::~CsvWriter() {
    if (file_) std::fclose(file_);
}

void CsvWriter::write(const MetricsRow& r) {
    std::fprintf(file_, "%u", r.t);
    for (const double v : {r.population, r.mean_vision, r.mean_metabolism, r.mean_sugar, r.gini, r.mean_neighbors,
                           r.moved, r.ne_fraction, r.on_peak_fraction, r.north_frac_high_vision, r.north_frac_low_vision,
                           r.summer_north}) {
        put(file_, v);
    }
    std::fputc('\n', file_);
    std::fflush(file_);
}
