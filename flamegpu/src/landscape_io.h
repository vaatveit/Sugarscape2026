// Capacity maps (the Python project's load_map layout) and tiling.
#ifndef SRC_LANDSCAPE_IO_H_
#define SRC_LANDSCAPE_IO_H_

#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

struct MapError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

// Whitespace-separated non-negative integers, one line per row, the first line northernmost (y = height-1);
// blank lines are skipped. Returns capacities indexed x + y * width. Throws MapError naming the file and line.
std::vector<uint32_t> load_map(const std::string& path, int width, int height);

// The w x h map repeated k x k times; the result is indexed x + y * (w * k).
std::vector<uint32_t> tile_map(const std::vector<uint32_t>& map, int w, int h, int k);

// One starting agent from --init (header x,y,vision,metabolism,sugar,age,max_age; max_age blank = immortal), with
// optional further columns by name: sex (F, M or blank), fertility_start, fertility_end, initial_sugar (default
// sugar), tags (a 0/1 string, tag 0 first), n_children, parent_a and parent_b.
struct InitAgent {
    int x, y, vision, metabolism;
    double sugar;
    int age;
    std::optional<int> max_age;
    unsigned int sex = 0;  // model.h's SEX_NONE / SEX_F / SEX_M
    std::optional<int> fertility_start, fertility_end;
    std::optional<double> initial_sugar;
    uint64_t tags = 0;
    unsigned int n_children = 0;  // children had before the run (tests: mean_children)
    std::optional<unsigned int> parent_a, parent_b;  // the uid (row in the file) of each parent (tests: rule I)
};

// Throws MapError naming the file and line on a bad header, field, or site outside width x height, or two
// agents on one site.
std::vector<InitAgent> load_init_agents(const std::string& path, int width, int height);

#endif  // SRC_LANDSCAPE_IO_H_
