// --dump-agents / --dump-landscape writers and the --check invariants (design: Verification 3).
#include <algorithm>
#include <cstdio>
#include <set>
#include <string>
#include <tuple>

#include "host_state.h"
#include "model.h"

namespace {

struct CitizenRow {
    int x, y, vision, metabolism, age, max_age;
    float sugar;
    unsigned int moved, neighbors;
    unsigned int id, priority, dir_order, look_seed;  // the period's order and looks (spec 2026-10-25, section 4)
};

std::vector<CitizenRow> citizens(flamegpu::HostAPI* api) {
    flamegpu::DeviceAgentVector pop = api->agent("citizen").getPopulationData();
    std::vector<CitizenRow> rows;
    rows.reserve(pop.size());
    for (unsigned int i = 0; i < pop.size(); ++i) {
        const auto a = pop[i];
        rows.push_back({a.getVariable<int>("x"), a.getVariable<int>("y"), a.getVariable<int>("vision"),
                        a.getVariable<int>("metabolism"), a.getVariable<int>("age"), a.getVariable<int>("max_age"),
                        a.getVariable<float>("sugar"), a.getVariable<unsigned int>("moved"),
                        a.getVariable<unsigned int>("neighbors"), a.getID(), a.getVariable<unsigned int>("priority"),
                        a.getVariable<unsigned int>("dir_order"), a.getVariable<unsigned int>("look_seed")});
    }
    std::sort(rows.begin(), rows.end(), [](const CitizenRow& a, const CitizenRow& b) {
        return std::tie(a.x, a.y) < std::tie(b.x, b.y);
    });
    return rows;
}

FILE* open_or_throw(const std::string& path) {
    FILE* f = std::fopen(path.c_str(), "w");
    if (!f) throw std::runtime_error("cannot write " + path);
    return f;
}

}  // namespace

void write_dumps(flamegpu::HostAPI* api, unsigned int t) {
    const RunState& s = state();
    if (!s.dump_at || *s.dump_at != t) return;
    if (!s.dump_agents.empty()) {
        FILE* f = open_or_throw(s.dump_agents);
        std::fprintf(f, "x,y,vision,metabolism,sugar,age,max_age,moved,neighbors,id,priority,dir_order,look_seed\n");
        for (const CitizenRow& a : citizens(api)) {
            std::fprintf(f, "%d,%d,%d,%d,%.17g,%d,", a.x, a.y, a.vision, a.metabolism, static_cast<double>(a.sugar), a.age);
            if (a.max_age != IMMORTAL) std::fprintf(f, "%d", a.max_age);
            std::fprintf(f, ",%u,%u,%u,%u,%u,%u\n", a.moved, a.neighbors, a.id, a.priority, a.dir_order, a.look_seed);
        }
        std::fclose(f);
    }
    if (!s.dump_landscape.empty()) {
        auto sugar = api->environment.getMacroProperty<float, MAX_CELLS>("sugar");
        auto pollution = api->environment.getMacroProperty<float, MAX_CELLS>("pollution");
        auto occupied = api->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
        FILE* f = open_or_throw(s.dump_landscape);
        std::fprintf(f, "x,y,capacity,sugar,pollution,occupied\n");
        const int w = s.cfg.width, h = s.cfg.height;
        for (int x = 0; x < w; ++x) {
            for (int y = 0; y < h; ++y) {
                const unsigned int i = static_cast<unsigned int>(x + y * w);
                std::fprintf(f, "%d,%d,%u,%.17g,%.17g,%u\n", x, y, s.capacity[i], static_cast<double>(static_cast<float>(sugar[i])),
                             static_cast<double>(static_cast<float>(pollution[i])), static_cast<unsigned int>(occupied[i]));
            }
        }
        std::fclose(f);
    }
}

void check_invariants(flamegpu::HostAPI* api, unsigned int t, unsigned int deaths, unsigned int births) {
    const RunState& s = state();
    if (!s.check) return;
    auto fail = [t](const std::string& what) { throw InvariantError("t=" + std::to_string(t) + ": " + what); };
    const auto agents = citizens(api);
    const unsigned int expected = s.population - deaths + births;
    if (agents.size() != expected) {
        fail("population " + std::to_string(agents.size()) + " != " + std::to_string(s.population) + " - " +
             std::to_string(deaths) + " deaths + " + std::to_string(births) + " births");
    }
    auto sugar = api->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto occupied = api->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    const int w = s.cfg.width, h = s.cfg.height;
    std::set<unsigned int> sites;
    for (const CitizenRow& a : agents) {
        if (a.x < 0 || a.x >= w || a.y < 0 || a.y >= h) fail("agent outside the world");
        const unsigned int i = static_cast<unsigned int>(a.x + a.y * w);
        if (!sites.insert(i).second) fail("two agents on site " + std::to_string(a.x) + "," + std::to_string(a.y));
        if (static_cast<unsigned int>(occupied[i]) != 1u) fail("occupied is 0 under an agent");
        if (!(a.sugar > 0.0f)) fail("an agent survived with sugar <= 0");
    }
    unsigned long long occupied_count = 0;
    for (unsigned int i = 0; i < static_cast<unsigned int>(s.capacity.size()); ++i) {
        occupied_count += static_cast<unsigned int>(occupied[i]);
        const float v = sugar[i];
        if (!(v >= 0.0f && v <= static_cast<float>(s.capacity[i]))) fail("site sugar outside [0, capacity]");
    }
    if (occupied_count != agents.size()) fail("occupied count != population");
}
