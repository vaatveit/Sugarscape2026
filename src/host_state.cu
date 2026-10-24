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

void write_metrics(flamegpu::HostAPI* api, unsigned int t) {
    RunState& s = state();
    if (!s.csv || t % s.metrics_every != 0) return;
    flamegpu::DeviceAgentVector pop = api->agent("citizen").getPopulationData();
    AgentColumns c;
    const unsigned int n = pop.size();
    for (auto* v : {&c.x, &c.y, &c.vision, &c.metabolism}) v->reserve(n);
    for (unsigned int i = 0; i < n; ++i) {
        const auto a = pop[i];
        c.x.push_back(a.getVariable<int>("x"));
        c.y.push_back(a.getVariable<int>("y"));
        c.vision.push_back(a.getVariable<int>("vision"));
        c.metabolism.push_back(a.getVariable<int>("metabolism"));
        c.sugar.push_back(a.getVariable<float>("sugar"));
        c.moved.push_back(a.getVariable<unsigned int>("moved"));
        c.neighbors.push_back(a.getVariable<unsigned int>("neighbors"));
    }
    s.csv->write(compute_metrics(c, s.cfg, s.capacity, t));
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
    write_metrics(FLAMEGPU, 0);
}

FLAMEGPU_HOST_FUNCTION(begin_period) {
    const RunConfig& cfg = state().cfg;
    const int t = static_cast<int>(FLAMEGPU->getStepCounter());  // Python's Model.t during the period
    // P (p.47): active from pollution_start until pollution_stop (Python movement.pollution_active).
    const bool polluting = cfg.pollution && t >= cfg.pollution_start && (!cfg.pollution_stop || t < *cfg.pollution_stop);
    // D_alpha (p.48): every diffusion_period periods from diffusion_start (Python Model.step).
    const bool diffusing = cfg.diffusion_period && t >= cfg.diffusion_start && t % *cfg.diffusion_period == 0;
    FLAMEGPU->environment.setProperty<unsigned int>("t", static_cast<unsigned int>(t));
    FLAMEGPU->environment.setProperty<unsigned int>("round", 1u);
    FLAMEGPU->environment.setProperty<unsigned int>("pollution_active", polluting ? 1u : 0u);
    FLAMEGPU->environment.setProperty<unsigned int>("diffuse_now", diffusing ? 1u : 0u);
}

// R[a,b] (p.32): each agent that died this period is replaced by a new random agent at a random empty site,
// as Python's spawn_random_agent; newcomers do not harvest on arrival.
FLAMEGPU_HOST_FUNCTION(replace_dead) {
    RunState& s = state();
    s.births = 0;
    if (!s.cfg.replacement) return;
    const unsigned int deaths = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
    if (deaths == 0) return;
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    std::vector<uint32_t> empty;
    for (uint32_t i = 0; i < static_cast<uint32_t>(s.capacity.size()); ++i) {
        if (static_cast<unsigned int>(occupied[i]) == 0u) empty.push_back(i);
    }
    flamegpu::HostAgentAPI citizens = FLAMEGPU->agent("citizen");
    const RunConfig& cfg = s.cfg;
    for (unsigned int k = 0; k < deaths; ++k) {
        if (empty.empty()) throw std::runtime_error("no empty site for a new agent: the lattice is full");
        const size_t pick = std::uniform_int_distribution<size_t>(0, empty.size() - 1)(s.rng);
        const uint32_t site = empty[pick];
        empty[pick] = empty.back();
        empty.pop_back();
        occupied[site] = 1u;
        flamegpu::HostNewAgentAPI a = citizens.newAgent();
        a.setVariable<int>("x", static_cast<int>(site % cfg.width));
        a.setVariable<int>("y", static_cast<int>(site / cfg.width));
        a.setVariable<int>("vision", draw(s.rng, cfg.vision));
        a.setVariable<int>("metabolism", draw(s.rng, cfg.metabolism));
        a.setVariable<float>("sugar", static_cast<float>(draw(s.rng, cfg.endowment)));
        a.setVariable<int>("max_age", draw(s.rng, *cfg.max_age));  // validate(): replacement needs max_age
        a.setVariable<int>("age", 0);
    }
    s.births = deaths;
}

FLAMEGPU_STEP_FUNCTION(end_period) {
    RunState& s = state();
    const unsigned int t = FLAMEGPU->getStepCounter() + 1;  // the period just completed
    auto deaths_prop = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
    const unsigned int deaths = deaths_prop;
    deaths_prop = 0u;
    write_dumps(FLAMEGPU, t);
    check_invariants(FLAMEGPU, t, deaths, s.births);
    write_metrics(FLAMEGPU, t);
    s.population = FLAMEGPU->agent("citizen").count();
}
