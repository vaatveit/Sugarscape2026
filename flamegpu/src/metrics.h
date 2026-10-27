// Per-period metrics with the meaning of the Python project's experiments.run.sugarscape_metrics: standard_metrics,
// society_metrics, economic_metrics and disease_metrics, in that order (spec 2026-10-25-gpu-full-parity, section 7).
#ifndef SRC_METRICS_H_
#define SRC_METRICS_H_

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "config.h"

struct AgentColumns {
    std::vector<int> x, y, vision, metabolism;
    std::vector<double> sugar;
    std::vector<uint32_t> moved, neighbors;
    // Chapter III.
    std::vector<uint64_t> tags;
    std::vector<uint32_t> uid, n_children, n_friends;
    std::vector<uint32_t> friend_uid;  // MAX_FRIENDS per agent, agent by agent
    std::vector<int> disp_x, disp_y;
    // Chapter IV.
    std::vector<double> spice;
    std::vector<int> foresight;
};

struct MetricsRow {
    unsigned int t;
    std::vector<double> values;  // one per metric_names() entry
};

// The CSV's metric columns after t, in Python's order (45).
const std::vector<std::string>& metric_names();

// Means and fractions of nothing are nan, as Python's safe_mean and _fraction; gini is nan for an empty or
// zero-wealth population. agents_ever counts every agent created so far, as Python's Model.agents_ever.
MetricsRow compute_metrics(const AgentColumns& agents, const RunConfig& cfg, const std::vector<uint32_t>& capacity,
                           unsigned int t, unsigned int agents_ever);

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
