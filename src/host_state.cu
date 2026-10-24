#include "host_state.h"

#include <algorithm>
#include <numeric>

#include "model.h"

RunState& state() {
    static RunState s;
    return s;
}

namespace {

int draw(std::mt19937_64& rng, const IntRange& r) { return std::uniform_int_distribution<int>(r.lo, r.hi)(rng); }

// Candidate starting sites: every site, or with block placement the block (wrapped as Python wraps it) in
// every tile.
std::vector<uint32_t> placement_sites(const RunConfig& cfg) {
    std::vector<uint32_t> sites;
    if (cfg.placement == "random") {
        sites.resize(static_cast<size_t>(cfg.cells()));
        std::iota(sites.begin(), sites.end(), 0u);
        return sites;
    }
    const int bw = cfg.base_width(), bh = cfg.base_height();
    for (int ty = 0; ty < cfg.tile; ++ty) {
        for (int tx = 0; tx < cfg.tile; ++tx) {
            for (int i = 0; i < cfg.block[2]; ++i) {
                for (int j = 0; j < cfg.block[3]; ++j) {
                    const int x = tx * bw + (cfg.block[0] + i) % bw;
                    const int y = ty * bh + (cfg.block[1] + j) % bh;
                    sites.push_back(static_cast<uint32_t>(x + y * cfg.width));
                }
            }
        }
    }
    return sites;
}

void set_citizen(flamegpu::AgentVector::Agent a, int x, int y, int vision, int metabolism, float sugar, int age,
                 int max_age) {
    a.setVariable<int>("x", x);
    a.setVariable<int>("y", y);
    a.setVariable<int>("vision", vision);
    a.setVariable<int>("metabolism", metabolism);
    a.setVariable<float>("sugar", sugar);
    a.setVariable<int>("age", age);
    a.setVariable<int>("max_age", max_age);
}

}  // namespace

flamegpu::AgentVector make_citizens(flamegpu::ModelDescription& model, const std::vector<InitAgent>* init) {
    RunState& s = state();
    const RunConfig& cfg = s.cfg;
    s.initial_sites.clear();
    if (init) {
        flamegpu::AgentVector pop(model.Agent("citizen"), static_cast<unsigned int>(init->size()));
        for (size_t i = 0; i < init->size(); ++i) {
            const InitAgent& a = (*init)[i];
            set_citizen(pop[static_cast<unsigned int>(i)], a.x, a.y, a.vision, a.metabolism, a.sugar, a.age,
                        a.max_age.value_or(IMMORTAL));
            s.initial_sites.push_back(static_cast<uint32_t>(a.x + a.y * cfg.width));
        }
        return pop;
    }
    // Sites chosen without replacement (partial Fisher-Yates), then each agent's draws in Python's _spawn_at order.
    std::vector<uint32_t> sites = placement_sites(cfg);
    const size_t n = static_cast<size_t>(cfg.initial_population);
    for (size_t i = 0; i < n; ++i) {
        std::swap(sites[i], sites[std::uniform_int_distribution<size_t>(i, sites.size() - 1)(s.rng)]);
    }
    flamegpu::AgentVector pop(model.Agent("citizen"), static_cast<unsigned int>(n));
    std::vector<int> max_ages(n);
    for (size_t i = 0; i < n; ++i) {
        const int vision = draw(s.rng, cfg.vision);
        const int metabolism = draw(s.rng, cfg.metabolism);
        const int sugar = draw(s.rng, cfg.endowment);
        max_ages[i] = cfg.max_age ? draw(s.rng, *cfg.max_age) : IMMORTAL;
        set_citizen(pop[static_cast<unsigned int>(i)], static_cast<int>(sites[i] % cfg.width),
                    static_cast<int>(sites[i] / cfg.width), vision, metabolism, static_cast<float>(sugar), 0, max_ages[i]);
        s.initial_sites.push_back(sites[i]);
    }
    // Founders of a society with finite lives start at ages U[0, max age) (Python Config.founder_ages).
    if (cfg.max_age && cfg.founder_ages == "uniform") {
        for (size_t i = 0; i < n; ++i) {
            pop[static_cast<unsigned int>(i)].setVariable<int>(
                "age", std::uniform_int_distribution<int>(0, max_ages[i] - 1)(s.rng));
        }
    }
    return pop;
}

flamegpu::AgentVector make_cells(flamegpu::ModelDescription& model) {
    // A cell's site index is its index in the population (DeviceAPI::getIndex()); cells never die or sort.
    return flamegpu::AgentVector(model.Agent("cell"), static_cast<unsigned int>(state().cfg.cells()));
}

FLAMEGPU_INIT_FUNCTION(init_landscape) {
    RunState& s = state();
    auto capacity = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("capacity");
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    for (size_t i = 0; i < s.capacity.size(); ++i) {
        capacity[static_cast<unsigned int>(i)] = s.capacity[i];
        sugar[static_cast<unsigned int>(i)] = static_cast<float>(s.capacity[i]);  // p.21: sites start at capacity
    }
    for (const uint32_t site : s.initial_sites) occupied[site] = 1u;
    s.population = static_cast<unsigned int>(s.initial_sites.size());
    write_dumps(FLAMEGPU, 0);
    check_invariants(FLAMEGPU, 0, 0, 0);
}

FLAMEGPU_HOST_FUNCTION(begin_period) {
    FLAMEGPU->environment.setProperty<unsigned int>("t", FLAMEGPU->getStepCounter());
    FLAMEGPU->environment.setProperty<unsigned int>("round", 1u);
}

FLAMEGPU_STEP_FUNCTION(end_period) {
    RunState& s = state();
    const unsigned int t = FLAMEGPU->getStepCounter() + 1;  // the period just completed
    auto deaths_prop = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
    const unsigned int deaths = deaths_prop;
    deaths_prop = 0u;
    write_dumps(FLAMEGPU, t);
    check_invariants(FLAMEGPU, t, deaths, 0);
    s.population = FLAMEGPU->agent("citizen").count();
}
