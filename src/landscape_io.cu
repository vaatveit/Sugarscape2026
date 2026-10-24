#include "landscape_io.h"

#include <fstream>
#include <sstream>

std::vector<uint32_t> load_map(const std::string& path, int width, int height) {
    std::ifstream in(path);
    if (!in) throw MapError(path + ": cannot open the map file");
    std::vector<std::vector<uint32_t>> rows;
    std::string line;
    int number = 0;
    while (std::getline(in, line)) {
        ++number;
        std::istringstream tokens(line);
        std::vector<uint32_t> row;
        std::string token;
        while (tokens >> token) {
            size_t used = 0;
            unsigned long value = 0;
            try {
                value = std::stoul(token, &used);
            } catch (const std::exception&) {
                used = 0;
            }
            if (used != token.size() || token[0] == '-') {
                throw MapError(path + " line " + std::to_string(number) + ": '" + token + "' is not a non-negative integer");
            }
            row.push_back(static_cast<uint32_t>(value));
        }
        if (row.empty()) continue;
        if (static_cast<int>(row.size()) != width) {
            throw MapError(path + " line " + std::to_string(number) + ": " + std::to_string(row.size()) +
                           " values, expected " + std::to_string(width));
        }
        rows.push_back(std::move(row));
    }
    if (static_cast<int>(rows.size()) != height) {
        throw MapError(path + ": " + std::to_string(rows.size()) + " rows, expected " + std::to_string(height));
    }
    std::vector<uint32_t> capacity(static_cast<size_t>(width) * height);
    for (int r = 0; r < height; ++r) {
        const int y = height - 1 - r;  // first line is the northern row
        for (int x = 0; x < width; ++x) capacity[x + static_cast<size_t>(y) * width] = rows[r][x];
    }
    return capacity;
}

std::vector<uint32_t> tile_map(const std::vector<uint32_t>& map, int w, int h, int k) {
    const int W = w * k, H = h * k;
    std::vector<uint32_t> tiled(static_cast<size_t>(W) * H);
    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) tiled[x + static_cast<size_t>(y) * W] = map[(x % w) + static_cast<size_t>(y % h) * w];
    }
    return tiled;
}
