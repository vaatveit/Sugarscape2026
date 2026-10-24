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

// One starting agent from --init (header x,y,vision,metabolism,sugar,age,max_age; max_age blank = immortal).
struct InitAgent {
    int x, y, vision, metabolism;
    float sugar;
    int age;
    std::optional<int> max_age;
};

// Throws MapError naming the file and line on a bad header, field, or site outside width x height, or two
// agents on one site.
std::vector<InitAgent> load_init_agents(const std::string& path, int width, int height);

#endif  // SRC_LANDSCAPE_IO_H_
