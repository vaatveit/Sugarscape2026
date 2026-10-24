// Per-period metrics with the meaning of the Python project's sugarscape.stats.standard_metrics.
#ifndef SRC_METRICS_H_
#define SRC_METRICS_H_

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "config.h"

struct AgentColumns {
    std::vector<int> x, y, vision, metabolism;
    std::vector<float> sugar;
    std::vector<uint32_t> moved, neighbors;
};

struct MetricsRow {
    unsigned int t;
    double population, mean_vision, mean_metabolism, mean_sugar, gini, mean_neighbors, moved, ne_fraction,
        on_peak_fraction, north_frac_high_vision, north_frac_low_vision, summer_north;
};

// Means and fractions of nothing are nan, as Python's safe_mean and _fraction; gini is nan for an empty or
// zero-wealth population.
MetricsRow compute_metrics(const AgentColumns& agents, const RunConfig& cfg, const std::vector<uint32_t>& capacity,
                           unsigned int t);

class CsvWriter {
 public:
    explicit CsvWriter(const std::string& path);
    ~CsvWriter();
    CsvWriter(const CsvWriter&) = delete;
    CsvWriter& operator=(const CsvWriter&) = delete;
    void write(const MetricsRow& row);

 private:
    FILE* file_;
};

#endif  // SRC_METRICS_H_
