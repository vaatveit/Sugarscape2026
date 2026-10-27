#include "host_state.h"

#include <algorithm>
#include <bitset>
#include <fstream>
#include <numeric>
#include <string>
#include <utility>

#include "disease.h"
#include "model.h"
#include "tribe.h"

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

// Python's infect (p.145): contract a disease (a canonical id) unless already carrying it or immune to it.
bool infect(std::vector<unsigned int>& diseases, uint64_t immune, unsigned int id) {
    const RunState& s = state();
    if (std::find(diseases.begin(), diseases.end(), id) != diseases.end()) return false;
    if (is_immune(immune, s.cfg.immune_length, s.disease_bits[id], static_cast<int>(s.disease_len[id]))) return false;
    diseases.push_back(id);
    return true;
}

// A citizen's Chapter V state; the diseases array exists only with disease on (model.cu).
void set_disease_state(flamegpu::AgentVector::Agent a, uint64_t genotype, uint64_t immune,
                       const std::vector<unsigned int>& diseases) {
    a.setVariable<uint64_t>("immune_genotype", genotype);
    a.setVariable<uint64_t>("immune", immune);
    a.setVariable<unsigned int>("n_diseases", static_cast<unsigned int>(diseases.size()));
    for (unsigned int k = 0; k < diseases.size(); ++k) {
        a.setVariable<uint8_t, MAX_DISEASES>("diseases", k, static_cast<uint8_t>(diseases[k]));
    }
}

std::string bit_string(uint64_t bits, int length) {
    std::string out;
    for (int i = 0; i < length; ++i) out += (bits >> i) & 1u ? '1' : '0';
    return out;
}

}  // namespace

void make_disease_list(const std::string& path, const std::string& dump) {
    RunState& s = state();
    const RunConfig& cfg = s.cfg;
    if (!cfg.disease()) return;
    s.disease_bits.clear();
    s.disease_len.clear();
    if (path.empty()) {  // Python: each disease's length from disease_length, then its bits
        for (int i = 0; i < cfg.disease_list; ++i) {
            const int len = draw(s.rng, cfg.disease_length);
            s.disease_len.push_back(static_cast<unsigned int>(len));
            s.disease_bits.push_back(random_tags(s.rng, len, ""));
        }
    } else {  // --disease-list (ruling D1)
        std::ifstream in(path);
        if (!in) throw MapError(path + ": cannot open the disease list");
        std::string line;
        int number = 0;
        while (std::getline(in, line)) {
            ++number;
            if (!line.empty() && line.back() == '\r') line.pop_back();
            const std::string where = path + " line " + std::to_string(number) + ": ";
            if (line.empty() || line.find_first_not_of("01") != std::string::npos) {
                throw MapError(where + "expected a 0/1 string");
            }
            if (static_cast<int>(line.size()) >= cfg.immune_length) {
                throw MapError(where + "a disease of " + std::to_string(line.size()) +
                               " bits is not shorter than immune_length = " + std::to_string(cfg.immune_length));
            }
            uint64_t bits = 0;
            for (size_t i = 0; i < line.size(); ++i) bits |= static_cast<uint64_t>(line[i] == '1') << i;
            s.disease_bits.push_back(bits);
            s.disease_len.push_back(static_cast<unsigned int>(line.size()));
        }
        if (static_cast<int>(s.disease_bits.size()) != cfg.disease_list) {
            throw MapError(path + ": " + std::to_string(s.disease_bits.size()) + " diseases, but disease_list = " +
                           std::to_string(cfg.disease_list));
        }
    }
    s.disease_canon.assign(s.disease_bits.size(), 0u);
    for (size_t i = 0; i < s.disease_bits.size(); ++i) {
        size_t j = 0;
        while (s.disease_bits[j] != s.disease_bits[i] || s.disease_len[j] != s.disease_len[i]) ++j;
        s.disease_canon[i] = static_cast<unsigned int>(j);
    }
    if (dump.empty()) return;
    std::ofstream out(dump);
    if (!out) throw MapError("cannot write " + dump);
    out << "index,canonical,bits\n";
    for (size_t i = 0; i < s.disease_bits.size(); ++i) {
        out << i << "," << s.disease_canon[i] << "," << bit_string(s.disease_bits[i], static_cast<int>(s.disease_len[i]))
            << "\n";
    }
}

void canonical_init_diseases(const std::string& path, std::vector<InitAgent>& agents) {
    const RunState& s = state();
    for (InitAgent& a : agents) {
        for (size_t k = 0; k < a.diseases.size(); ++k) {
            const unsigned int id = s.disease_canon[a.diseases[k]];
            for (size_t j = 0; j < k; ++j) {
                if (a.diseases[j] == id) {
                    throw MapError(path + " line " + std::to_string(a.line) + ": diseases carried twice (master " +
                                   "indices of one string), which infection never gives");
                }
            }
            a.diseases[k] = id;
        }
    }
}

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
            agent.setVariable<unsigned int>("parent_a", a.parent_a.value_or(NO_UID));
            agent.setVariable<unsigned int>("parent_b", a.parent_b.value_or(NO_UID));
            agent.setVariable<unsigned int>("n_friends", static_cast<unsigned int>(a.friends.size()));
            for (unsigned int f = 0; f < a.friends.size(); ++f) {
                agent.setVariable<unsigned int, MAX_FRIENDS>("friend_uid", f, a.friends[f].first);
                agent.setVariable<unsigned int, MAX_FRIENDS>("friend_dist", f, a.friends[f].second);
            }
            if (a.sex != SEX_NONE) {
                agent.setVariable<unsigned int>("sex", a.sex);
                agent.setVariable<int>("fertility_start", a.fertility_start.value_or(NO_FERTILITY_START));
                agent.setVariable<int>("fertility_end", a.fertility_end.value_or(NO_FERTILITY_END));
            }
            // Chapter IV: the initial spice defaults to the spice, as initial_sugar to the sugar.
            agent.setVariable<double>("spice", a.spice.value_or(0.0));
            agent.setVariable<double>("initial_spice", a.initial_spice.value_or(a.spice.value_or(0.0)));
            agent.setVariable<int>("spice_metabolism", a.spice_metabolism.value_or(0));
            agent.setVariable<int>("foresight", a.foresight.value_or(0));
            // Chapter V (ruling D2): the diseases are the column's canonical ids; diseases_per_agent infects no one.
            if (cfg.disease()) {
                set_disease_state(agent, a.genotype_count >= 0 ? a.immune_genotype : a.immune, a.immune, a.diseases);
            }
        }
        s.next_uid = s.agents_ever = static_cast<unsigned int>(init->size());
        return pop;
    }
    const auto sites = founder_sites(s.rng, cfg);
    const size_t n = sites.size();
    flamegpu::AgentVector pop(model.Agent("citizen"), static_cast<unsigned int>(n));
    std::vector<int> max_ages(n);
    std::vector<uint64_t> genotypes(n);
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
        // Chapter IV's draws come last: spice metabolism, spice (= initial spice), then foresight when it is set.
        if (cfg.spice) {
            agent.setVariable<int>("spice_metabolism", draw(s.rng, cfg.spice_metabolism));
            const double spice = static_cast<double>(draw(s.rng, cfg.spice_endowment.value_or(cfg.endowment)));
            agent.setVariable<double>("spice", spice);
            agent.setVariable<double>("initial_spice", spice);
            if (cfg.foresight) agent.setVariable<int>("foresight", draw(s.rng, *cfg.foresight));
        }
        // Chapter V's draw comes last: the immune genotype, which the phenotype copies (p.146).
        if (cfg.disease()) {
            genotypes[i] = random_tags(s.rng, cfg.immune_length, "");
            agent.setVariable<uint64_t>("immune_genotype", genotypes[i]);
            agent.setVariable<uint64_t>("immune", genotypes[i]);
        }
    }
    s.next_uid = s.agents_ever = static_cast<unsigned int>(n);
    // p.147: once every founder is placed, each is offered diseases_per_agent distinct entries of the master list, in
    // the order Python's rng.choice(replace=False) picks them (partial Fisher-Yates), and infected by each it can catch.
    if (cfg.disease() && cfg.diseases_per_agent) {
        std::vector<unsigned int> pick(s.disease_bits.size()), carried;
        for (size_t i = 0; i < n; ++i) {
            std::iota(pick.begin(), pick.end(), 0u);
            carried.clear();
            for (size_t k = 0; k < static_cast<size_t>(cfg.diseases_per_agent); ++k) {
                std::swap(pick[k], pick[std::uniform_int_distribution<size_t>(k, pick.size() - 1)(s.rng)]);
                infect(carried, genotypes[i], s.disease_canon[pick[k]]);
            }
            set_disease_state(pop[static_cast<unsigned int>(i)], genotypes[i], genotypes[i], carried);
        }
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
    RunState& s = state();
    const std::vector<uint32_t>& capacity = s.capacity;
    // Fig IV-1: spice mountains NW and SE, the sugar map mirrored east-west (Python's capacity[::-1, :]).
    const size_t w = static_cast<size_t>(s.cfg.width);
    s.spice_capacity.assign(capacity.size(), 0u);
    if (s.cfg.spice) {
        for (size_t i = 0; i < capacity.size(); ++i) s.spice_capacity[i] = capacity[(w - 1 - i % w) + i / w * w];
    }
    flamegpu::AgentVector cells(model.Agent("cell"), static_cast<unsigned int>(capacity.size()));
    for (size_t i = 0; i < capacity.size(); ++i) {
        cells[static_cast<unsigned int>(i)].setVariable<unsigned int>("capacity", capacity[i]);
        cells[static_cast<unsigned int>(i)].setVariable<unsigned int>("spice_capacity", s.spice_capacity[i]);
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
    c.spice = column<double>(pop, "spice");
    c.foresight = column<int>(pop, "foresight");
    c.n_diseases = column<uint32_t>(pop, "n_diseases");
    if (s.cfg.disease() && pop.size()) {  // the array exists only with disease on (model.cu)
        const uint8_t* d = pop.data<uint8_t>("diseases");
        c.diseases.assign(d, d + pop.size() * MAX_DISEASES);
    }
    {
        const uint32_t* f = pop.size() ? pop.data<uint32_t>("friend_uid") : nullptr;
        c.friend_uid = f ? std::vector<uint32_t>(f, f + pop.size() * MAX_FRIENDS) : std::vector<uint32_t>();
    }
    const auto row = compute_metrics(c, s.cfg, s.capacity, t, s.agents_ever, t == 0 ? TradeTotals{} : s.trades,
                                     s.loans ? s.loans->to_host() : std::vector<LoanRecord>{});
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
    // R's newcomers were born on the device, one for each death (rules.cuh, output_newcomer), and rule S's children.
    check_invariants(FLAMEGPU, t, deaths, (s.cfg.replacement ? deaths : 0u) + s.newborns_this_period);
    s.newborns_this_period = 0;
    s.population = FLAMEGPU->agent("citizen").count();
}
