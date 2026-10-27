#include "landscape_io.h"

#include <fstream>
#include <set>
#include <sstream>

#include "config.h"

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
                                                       "tags",       "n_children",      "parent_a",      "parent_b",
                                                       "friends",    "spice",           "initial_spice", "spice_metabolism",
                                                       "foresight",  "immune_genotype", "immune",        "diseases"};
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
                } else if (header[c] == "friends") {
                    std::stringstream fs(v);
                    std::string item;
                    while (std::getline(fs, item, '|')) {
                        const auto colon = item.find(':');
                        if (colon == std::string::npos) throw MapError(where + ": friends must be uid:distance|...");
                        a.friends.emplace_back(static_cast<unsigned int>(std::stoul(item.substr(0, colon))),
                                               static_cast<unsigned int>(std::stoul(item.substr(colon + 1))));
                    }
                    if (a.friends.size() > 5) throw MapError(where + ": at most 5 friends");
                } else if (header[c] == "parent_a") {
                    a.parent_a = static_cast<unsigned int>(std::stoul(v));
                } else if (header[c] == "parent_b") {
                    a.parent_b = static_cast<unsigned int>(std::stoul(v));
                } else if (header[c] == "initial_sugar") {
                    a.initial_sugar = std::stod(v);
                } else if (header[c] == "spice") {
                    a.spice = std::stod(v);
                } else if (header[c] == "initial_spice") {
                    a.initial_spice = std::stod(v);
                } else if (header[c] == "spice_metabolism") {
                    a.spice_metabolism = std::stoi(v);
                } else if (header[c] == "foresight") {
                    a.foresight = std::stoi(v);
                } else if (header[c] == "tags") {
                    if (v.size() > 63 || v.find_first_not_of("01") != std::string::npos) {
                        throw MapError(where + ": tags must be a 0/1 string of at most 63 bits");
                    }
                    for (size_t i = 0; i < v.size(); ++i) a.tags |= static_cast<uint64_t>(v[i] == '1') << i;
                    a.tag_count = static_cast<int>(v.size());
                } else if (header[c] == "immune" || header[c] == "immune_genotype") {
                    if (v.size() > 64 || v.find_first_not_of("01") != std::string::npos) {
                        throw MapError(where + ": " + header[c] + " must be a 0/1 string of at most 64 bits");
                    }
                    uint64_t bits = 0;
                    for (size_t i = 0; i < v.size(); ++i) bits |= static_cast<uint64_t>(v[i] == '1') << i;
                    (header[c] == "immune" ? a.immune : a.immune_genotype) = bits;
                    (header[c] == "immune" ? a.immune_count : a.genotype_count) = static_cast<int>(v.size());
                } else if (header[c] == "diseases") {  // master indices joined by '|'
                    std::stringstream ds(v);
                    std::string item;
                    while (std::getline(ds, item, '|')) a.diseases.push_back(static_cast<unsigned int>(std::stoul(item)));
                }
            }
            a.line = number;
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

void check_init_agents(const std::string& path, const std::vector<InitAgent>& agents, const RunConfig& cfg) {
    const int stride = cfg.look_stride;
    const auto n = static_cast<unsigned int>(agents.size());
    for (const InitAgent& a : agents) {
        const std::string where = path + " line " + std::to_string(a.line) + ": ";
        if (cfg.sex && cfg.mate_contact == "vision" && a.vision / stride > MAX_SIGHT_LOOKS) {
            throw MapError(where + "partners in sight look " + std::to_string(a.vision / stride) +
                           " sites along each line, beyond the GPU's limit of " + std::to_string(MAX_SIGHT_LOOKS));
        }
        if (!cfg.spice && (a.spice || a.initial_spice || a.spice_metabolism || a.foresight)) {
            throw MapError(where + "spice values given, but spice = false");
        }
        // Chapter V (ruling D2): with disease on, the immune strings Python's _spawn_at would have drawn.
        const bool disease_given = a.immune_count >= 0 || a.genotype_count >= 0 || !a.diseases.empty();
        if (!cfg.disease() && disease_given) throw MapError(where + "disease columns given, but disease_list = 0");
        if (cfg.disease()) {
            if (a.immune_count < 0) throw MapError(where + "with disease on, every agent needs its immune string");
            for (const int count : {a.immune_count, a.genotype_count}) {
                if (count >= 0 && count != cfg.immune_length) {
                    throw MapError(where + std::to_string(count) + " immune bits given, but immune_length = " +
                                   std::to_string(cfg.immune_length));
                }
            }
            for (const unsigned int d : a.diseases) {
                if (d >= static_cast<unsigned int>(cfg.disease_list)) {
                    throw MapError(where + "disease " + std::to_string(d) + " is not in the master list of " +
                                   std::to_string(cfg.disease_list));
                }
            }
        }
        if (a.tag_count >= 0 && a.tag_count != cfg.tag_length) {
            throw MapError(where + std::to_string(a.tag_count) + " tags given, but tag_length = " +
                           std::to_string(cfg.tag_length));
        }
        for (const auto& parent : {a.parent_a, a.parent_b}) {
            if (parent && *parent >= n) {
                throw MapError(where + "parent " + std::to_string(*parent) + " is not an agent of the file (" +
                               std::to_string(n) + " agents)");
            }
        }
        for (const auto& [uid, dist] : a.friends) {
            if (uid >= n) {
                throw MapError(where + "friend " + std::to_string(uid) + " is not an agent of the file (" +
                               std::to_string(n) + " agents)");
            }
        }
    }
}
