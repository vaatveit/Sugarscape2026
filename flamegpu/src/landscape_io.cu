#include "landscape_io.h"

#include <fstream>
#include <set>
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

std::vector<InitAgent> load_init_agents(const std::string& path, int width, int height) {
    std::ifstream in(path);
    if (!in) throw MapError(path + ": cannot open the init file");
    std::string line;
    if (!std::getline(in, line) || line.find("x,y,vision,metabolism,sugar,age,max_age") != 0) {
        throw MapError(path + " line 1: expected the header x,y,vision,metabolism,sugar,age,max_age");
    }
    if (!line.empty() && line.back() == '\r') line.pop_back();
    std::vector<std::string> header;
    {
        std::stringstream hs(line);
        std::string name;
        while (std::getline(hs, name, ',')) header.push_back(name);
    }
    for (size_t c = 7; c < header.size(); ++c) {
        static const std::set<std::string> optional = {"sex",        "fertility_start", "fertility_end", "initial_sugar",
                                                       "tags",       "n_children",      "parent_a",      "parent_b"};
        if (!optional.count(header[c])) throw MapError(path + " line 1: unknown column '" + header[c] + "'");
    }
    std::vector<InitAgent> agents;
    std::set<long long> sites;
    int number = 1;
    while (std::getline(in, line)) {
        ++number;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        std::vector<std::string> f;
        std::stringstream ss(line);
        std::string part;
        while (std::getline(ss, part, ',')) f.push_back(part);
        if (line.back() == ',') f.push_back("");
        const std::string where = path + " line " + std::to_string(number);
        if (f.size() != header.size()) throw MapError(where + ": expected " + std::to_string(header.size()) + " fields");
        try {
            InitAgent a{std::stoi(f[0]), std::stoi(f[1]), std::stoi(f[2]), std::stoi(f[3]), std::stod(f[4]),
                        std::stoi(f[5]), f[6].empty() ? std::nullopt : std::optional<int>(std::stoi(f[6]))};
            for (size_t c = 7; c < header.size(); ++c) {
                const std::string& v = f[c];
                if (v.empty()) continue;
                if (header[c] == "sex") {
                    if (v != "F" && v != "M") throw MapError(where + ": sex must be F, M or blank");
                    a.sex = v == "F" ? 1u : 2u;
                } else if (header[c] == "fertility_start") {
                    a.fertility_start = std::stoi(v);
                } else if (header[c] == "fertility_end") {
                    a.fertility_end = std::stoi(v);
                } else if (header[c] == "n_children") {
                    a.n_children = static_cast<unsigned int>(std::stoul(v));
                } else if (header[c] == "parent_a") {
                    a.parent_a = static_cast<unsigned int>(std::stoul(v));
                } else if (header[c] == "parent_b") {
                    a.parent_b = static_cast<unsigned int>(std::stoul(v));
                } else if (header[c] == "initial_sugar") {
                    a.initial_sugar = std::stod(v);
                } else if (header[c] == "tags") {
                    if (v.size() > 63 || v.find_first_not_of("01") != std::string::npos) {
                        throw MapError(where + ": tags must be a 0/1 string of at most 63 bits");
                    }
                    for (size_t i = 0; i < v.size(); ++i) a.tags |= static_cast<uint64_t>(v[i] == '1') << i;
                }
            }
            if (a.x < 0 || a.x >= width || a.y < 0 || a.y >= height) throw MapError(where + ": site outside the world");
            if (!sites.insert(a.x + static_cast<long long>(a.y) * width).second) throw MapError(where + ": site already taken");
            agents.push_back(a);
        } catch (const std::invalid_argument&) {
            throw MapError(where + ": not a number");
        } catch (const std::out_of_range&) {
            throw MapError(where + ": number out of range");
        }
    }
    return agents;
}
