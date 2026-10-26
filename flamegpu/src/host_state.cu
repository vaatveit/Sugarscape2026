#include "host_state.h"

#include <algorithm>
#include <bitset>
#include <numeric>
#include <string>
#include <utility>

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

void set_citizen(flamegpu::AgentVector::Agent a, unsigned int uid, int x, int y, int vision, int metabolism,
                 double sugar, int age, int max_age) {
    a.setVariable<unsigned int>("uid", uid);
    a.setVariable<int>("x", x);
    a.setVariable<int>("y", y);
    a.setVariable<int>("vision", vision);
    a.setVariable<int>("metabolism", metabolism);
    a.setVariable<double>("sugar", sugar);
    a.setVariable<double>("initial_sugar", sugar);
    a.setVariable<int>("age", age);
    a.setVariable<int>("max_age", max_age);
}

// Python's culture.tribe: Blue when 0s outnumber 1s, Red otherwise.
bool is_blue(uint64_t tags, int length) { return 2 * static_cast<int>(std::bitset<64>(tags).count()) < length; }

// Python's random_tags: uniform bits, resampled until the majority matches the tribe ("" for any).
uint64_t random_tags(std::mt19937_64& rng, int length, const std::string& tribe) {
    while (true) {
        uint64_t tags = 0;
        for (int i = 0; i < length; ++i) tags |= static_cast<uint64_t>(std::uniform_int_distribution<int>(0, 1)(rng)) << i;
        if (tribe.empty() || (tribe == "blue") == is_blue(tags, length)) return tags;
    }
}

// Python's _assign_sex: sex, then childbearing ages drawn for that sex (p.57 fn 4).
void assign_sex(flamegpu::AgentVector::Agent a, std::mt19937_64& rng, const RunConfig& cfg, unsigned int sex) {
    a.setVariable<unsigned int>("sex", sex);
    a.setVariable<int>("fertility_start", draw(rng, cfg.fertility_start));
    a.setVariable<int>("fertility_end", draw(rng, sex == SEX_F ? cfg.female_fertility_end : cfg.male_fertility_end));
}

// Each founder's site and, for a tribal block, its tribe: blocks in order, each block's free sites (x-major, as
// Python lists them) chosen without replacement; otherwise Python's placement sites.
std::vector<std::pair<uint32_t, std::string>> founder_sites(std::mt19937_64& rng, const RunConfig& cfg) {
    std::vector<std::pair<uint32_t, std::string>> out;
    if (!cfg.initial_blocks.empty()) {
        std::vector<char> taken(static_cast<size_t>(cfg.cells()), 0);
        for (const TribeBlock& b : cfg.initial_blocks) {
            std::vector<uint32_t> sites;
            for (int i = 0; i < b.w; ++i) {
                for (int j = 0; j < b.h; ++j) {
                    const uint32_t site = static_cast<uint32_t>((b.x0 + i) + (b.y0 + j) * cfg.width);
                    if (!taken[site]) sites.push_back(site);
                }
            }
            if (static_cast<size_t>(b.n) > sites.size()) {
                throw ConfigError(std::to_string(b.n) + " " + b.tribe + " agents do not fit in " +
                                  std::to_string(sites.size()) + " empty block sites");
            }
            for (size_t k = 0; k < static_cast<size_t>(b.n); ++k) {
                std::swap(sites[k], sites[std::uniform_int_distribution<size_t>(k, sites.size() - 1)(rng)]);
                taken[sites[k]] = 1;
                out.emplace_back(sites[k], b.tribe);
            }
        }
        return out;
    }
    // Sites chosen without replacement (partial Fisher-Yates).
    std::vector<uint32_t> sites = placement_sites(cfg);
    const size_t n = static_cast<size_t>(cfg.initial_population);
    for (size_t i = 0; i < n; ++i) {
        std::swap(sites[i], sites[std::uniform_int_distribution<size_t>(i, sites.size() - 1)(rng)]);
        out.emplace_back(sites[i], std::string());
    }
    return out;
}

}  // namespace

flamegpu::AgentVector make_citizens(flamegpu::ModelDescription& model, const std::vector<InitAgent>* init) {
    RunState& s = state();
    const RunConfig& cfg = s.cfg;
    if (init) {
        flamegpu::AgentVector pop(model.Agent("citizen"), static_cast<unsigned int>(init->size()));
        for (size_t i = 0; i < init->size(); ++i) {
            const InitAgent& a = (*init)[i];
            auto agent = pop[static_cast<unsigned int>(i)];
            set_citizen(agent, static_cast<unsigned int>(i), a.x, a.y, a.vision, a.metabolism, a.sugar, a.age,
                        a.max_age.value_or(IMMORTAL));
            agent.setVariable<double>("initial_sugar", a.initial_sugar.value_or(a.sugar));
            agent.setVariable<uint64_t>("tags", a.tags);
            agent.setVariable<unsigned int>("n_children", a.n_children);
            if (a.sex != SEX_NONE) {
                agent.setVariable<unsigned int>("sex", a.sex);
                agent.setVariable<int>("fertility_start", a.fertility_start.value_or(NO_FERTILITY_START));
                agent.setVariable<int>("fertility_end", a.fertility_end.value_or(NO_FERTILITY_END));
            }
        }
        s.next_uid = s.agents_ever = static_cast<unsigned int>(init->size());
        return pop;
    }
    const auto sites = founder_sites(s.rng, cfg);
    const size_t n = sites.size();
    flamegpu::AgentVector pop(model.Agent("citizen"), static_cast<unsigned int>(n));
    std::vector<int> max_ages(n);
    // Each founder's draws in Python's _spawn_at order: Chapter II's, then tags, then sex, each only when on, so
    // Chapter II runs keep their random stream.
    for (size_t i = 0; i < n; ++i) {
        const int vision = draw_vision(s.rng, cfg);
        const int metabolism = draw(s.rng, cfg.metabolism);
        const int sugar = draw(s.rng, cfg.endowment);
        max_ages[i] = cfg.max_age ? draw(s.rng, *cfg.max_age) : IMMORTAL;
        auto agent = pop[static_cast<unsigned int>(i)];
        set_citizen(agent, static_cast<unsigned int>(i), static_cast<int>(sites[i].first % cfg.width),
                    static_cast<int>(sites[i].first / cfg.width), vision, metabolism, static_cast<double>(sugar), 0,
                    max_ages[i]);
        if (cfg.tag_length) agent.setVariable<uint64_t>("tags", random_tags(s.rng, cfg.tag_length, sites[i].second));
        if (cfg.sex) assign_sex(agent, s.rng, cfg, std::uniform_int_distribution<int>(0, 1)(s.rng) == 0 ? SEX_F : SEX_M);
    }
    s.next_uid = s.agents_ever = static_cast<unsigned int>(n);
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
    c.sugar = column<double>(pop, "sugar");
    c.moved = column<uint32_t>(pop, "moved");
    c.neighbors = column<uint32_t>(pop, "neighbors");
    c.tags = column<uint64_t>(pop, "tags");
    c.uid = column<uint32_t>(pop, "uid");
    c.n_children = column<uint32_t>(pop, "n_children");
    c.n_friends = column<uint32_t>(pop, "n_friends");
    c.disp_x = column<int>(pop, "disp_x");
    c.disp_y = column<int>(pop, "disp_y");
    {
        const uint32_t* f = pop.size() ? pop.data<uint32_t>("friend_uid") : nullptr;
        c.friend_uid = f ? std::vector<uint32_t>(f, f + pop.size() * MAX_FRIENDS) : std::vector<uint32_t>();
    }
    const auto row = compute_metrics(c, s.cfg, s.capacity, t, s.agents_ever);
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
    s.agents_ever = s.next_uid;
    if (s.store) s.waves.push_back(s.waves_this_period);
    write_dumps(FLAMEGPU, t);
    // R's newcomers were born on the device, one for each death (rules.cuh, output_newcomer).
    check_invariants(FLAMEGPU, t, deaths, s.cfg.replacement ? deaths : 0u);
    s.population = FLAMEGPU->agent("citizen").count();
}
