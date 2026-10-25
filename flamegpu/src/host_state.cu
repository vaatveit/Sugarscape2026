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

// Vision in whole look strides, stride * U[lo / stride, hi / stride] (Python Model._spawn_at). Stride 1 is the plain
// draw, so regular runs keep their random stream.
int draw_vision(std::mt19937_64& rng, const RunConfig& cfg) {
    const int s = cfg.look_stride;
    return s * draw(rng, IntRange{cfg.vision.lo / s, cfg.vision.hi / s});
}

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
    if (init) {
        flamegpu::AgentVector pop(model.Agent("citizen"), static_cast<unsigned int>(init->size()));
        for (size_t i = 0; i < init->size(); ++i) {
            const InitAgent& a = (*init)[i];
            set_citizen(pop[static_cast<unsigned int>(i)], a.x, a.y, a.vision, a.metabolism, a.sugar, a.age,
                        a.max_age.value_or(IMMORTAL));
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
        const int vision = draw_vision(s.rng, cfg);
        const int metabolism = draw(s.rng, cfg.metabolism);
        const int sugar = draw(s.rng, cfg.endowment);
        max_ages[i] = cfg.max_age ? draw(s.rng, *cfg.max_age) : IMMORTAL;
        set_citizen(pop[static_cast<unsigned int>(i)], static_cast<int>(sites[i] % cfg.width),
                    static_cast<int>(sites[i] / cfg.width), vision, metabolism, static_cast<float>(sugar), 0, max_ages[i]);
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
    const std::vector<uint32_t>& capacity = state().capacity;
    flamegpu::AgentVector cells(model.Agent("cell"), static_cast<unsigned int>(capacity.size()));
    for (size_t i = 0; i < capacity.size(); ++i) {
        cells[static_cast<unsigned int>(i)].setVariable<unsigned int>("capacity", capacity[i]);
    }
    return cells;
}

namespace {

// One variable's column, in agent order, through AgentVector's const column pointer (no per-agent lookups).
template <typename T>
std::vector<T> column(const flamegpu::AgentVector& pop, const char* name) {
    const T* p = pop.size() ? pop.data<T>(name) : nullptr;
    return p ? std::vector<T>(p, p + pop.size()) : std::vector<T>();
}

}  // namespace

void write_metrics(flamegpu::CUDASimulation* simulation, flamegpu::AgentVector& citizens, unsigned int t) {
    RunState& s = state();
    if (!s.csv || t % s.metrics_every != 0) return;
    const auto start = std::chrono::steady_clock::now();  // docs/xl.md's metrics: gathering, not writing
    if (simulation) simulation->getPopulationData(citizens);
    const flamegpu::AgentVector& pop = citizens;
    AgentColumns c;
    c.x = column<int>(pop, "x");
    c.y = column<int>(pop, "y");
    c.vision = column<int>(pop, "vision");
    c.metabolism = column<int>(pop, "metabolism");
    c.sugar = column<float>(pop, "sugar");
    c.moved = column<uint32_t>(pop, "moved");
    c.neighbors = column<uint32_t>(pop, "neighbors");
    const auto row = compute_metrics(c, s.cfg, s.capacity, t);
    s.metrics_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    s.csv->write(row);
}

FLAMEGPU_HOST_FUNCTION(begin_period) {
    RunState& s = state();
    if (s.timing) {
        cudaDeviceSynchronize();
        s.period_start = std::chrono::steady_clock::now();
    }
    const RunConfig& cfg = s.cfg;
    const int t = static_cast<int>(FLAMEGPU->getStepCounter());  // Python's Model.t during the period
    // P (p.47): active from pollution_start until pollution_stop (Python movement.pollution_active).
    const bool polluting = cfg.pollution && t >= cfg.pollution_start && (!cfg.pollution_stop || t < *cfg.pollution_stop);
    // D_alpha (p.48): every diffusion_period periods from diffusion_start (Python Model.step).
    const bool diffusing = cfg.diffusion_period && t >= cfg.diffusion_start && t % *cfg.diffusion_period == 0;
    FLAMEGPU->environment.setProperty<unsigned int>("t", static_cast<unsigned int>(t));
    FLAMEGPU->environment.setProperty<unsigned int>("round", 1u);
    FLAMEGPU->environment.setProperty<unsigned int>("pollution_active", polluting ? 1u : 0u);
    FLAMEGPU->environment.setProperty<unsigned int>("diffuse_now", diffusing ? 1u : 0u);
    // The pollution_diffusion sub-model runs the passes after cell_grow's first.
    FLAMEGPU->environment.setProperty<unsigned int>(
        "extra_passes", diffusing ? static_cast<unsigned int>(cfg.diffusion_passes - 1) : 0u);
    FLAMEGPU->environment.setProperty<unsigned int>("diffusion_pass", 0u);
    FLAMEGPU->environment.setProperty<unsigned int>("initialising", t == 0 ? 1u : 0u);
}

// After the first period's initialise layer (cell_initialise, occupy_site): the state at t = 0 and its outputs.
FLAMEGPU_HOST_FUNCTION(finish_init) {
    if (FLAMEGPU->getStepCounter() != 0) return;
    RunState& s = state();
    if (s.timing) {
        cudaDeviceSynchronize();
        s.setup_end = std::chrono::steady_clock::now();
    }
    s.population = FLAMEGPU->agent("citizen").count();
    write_dumps(FLAMEGPU, 0);
    check_invariants(FLAMEGPU, 0, 0, 0);
    // The first period starts now: initialisation is setup's. main made the t = 0 metrics row from the founders.
    if (s.timing) s.period_start = std::chrono::steady_clock::now();
}

FLAMEGPU_STEP_FUNCTION(end_period) {
    RunState& s = state();
    if (s.timing) {
        cudaDeviceSynchronize();  // kernels may still be running when step functions start
        s.period_seconds.push_back(std::chrono::duration<double>(std::chrono::steady_clock::now() - s.period_start).count());
    }
    const unsigned int t = FLAMEGPU->getStepCounter() + 1;  // the period just completed
    auto deaths_prop = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
    const unsigned int deaths = deaths_prop;
    deaths_prop = 0u;
    write_dumps(FLAMEGPU, t);
    // R's newcomers were born on the device, one for each death (rules.cuh, output_newcomer).
    check_invariants(FLAMEGPU, t, deaths, s.cfg.replacement ? deaths : 0u);
    s.population = FLAMEGPU->agent("citizen").count();
}
