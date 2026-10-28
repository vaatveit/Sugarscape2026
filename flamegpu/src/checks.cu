// --dump-agents / --dump-landscape writers and the --check invariants (design: Verification 3).
#include <algorithm>
#include <cstdio>
#include <set>
#include <string>
#include <tuple>
#include <vector>

#include "host_state.h"
#include "model.h"

namespace {

struct CitizenRow {
    int x, y, vision, metabolism, age, max_age;
    double sugar;
    unsigned int moved, neighbors;
    unsigned int id, priority, dir_order, look_seed;  // the period's order and looks (spec 2026-10-25, section 4)
    // Chapter III (spec 2026-10-25-gpu-full-parity, Task 2).
    unsigned int uid, sex;
    int fertility_start, fertility_end;
    double initial_sugar;
    uint64_t tags;
    unsigned int n_children, parent_a, parent_b, n_friends;
    int disp_x, disp_y;
    unsigned int friend_uid[MAX_FRIENDS], friend_dist[MAX_FRIENDS];
    // Chapter IV (plan 2026-10-26-gpu-parity-part-c, Task 2).
    double spice, initial_spice;
    int spice_metabolism, foresight;
    // Chapter V (plan 2026-10-27-gpu-parity-part-d, Task 2).
    uint64_t immune_genotype, immune;
    std::vector<unsigned int> diseases;  // canonical ids in infection order
};

std::vector<CitizenRow> citizens(flamegpu::HostAPI* api) {
    flamegpu::DeviceAgentVector pop = api->agent("citizen").getPopulationData();
    std::vector<CitizenRow> rows;
    rows.reserve(pop.size());
    for (unsigned int i = 0; i < pop.size(); ++i) {
        const auto a = pop[i];
        rows.push_back({a.getVariable<int>("x"), a.getVariable<int>("y"), a.getVariable<int>("vision"),
                        a.getVariable<int>("metabolism"), a.getVariable<int>("age"), a.getVariable<int>("max_age"),
                        a.getVariable<double>("sugar"), a.getVariable<unsigned int>("moved"),
                        a.getVariable<unsigned int>("neighbors"), a.getID(), a.getVariable<unsigned int>("priority"),
                        a.getVariable<unsigned int>("dir_order"), a.getVariable<unsigned int>("look_seed"),
                        a.getVariable<unsigned int>("uid"), a.getVariable<unsigned int>("sex"),
                        a.getVariable<int>("fertility_start"), a.getVariable<int>("fertility_end"),
                        a.getVariable<double>("initial_sugar"), a.getVariable<uint64_t>("tags"),
                        a.getVariable<unsigned int>("n_children"), a.getVariable<unsigned int>("parent_a"),
                        a.getVariable<unsigned int>("parent_b"), a.getVariable<unsigned int>("n_friends"),
                        a.getVariable<int>("disp_x"), a.getVariable<int>("disp_y"), {}, {},
                        a.getVariable<double>("spice"), a.getVariable<double>("initial_spice"),
                        a.getVariable<int>("spice_metabolism"), a.getVariable<int>("foresight")});
        for (unsigned int f = 0; f < MAX_FRIENDS; ++f) {
            rows.back().friend_uid[f] = a.getVariable<unsigned int, MAX_FRIENDS>("friend_uid", f);
            rows.back().friend_dist[f] = a.getVariable<unsigned int, MAX_FRIENDS>("friend_dist", f);
        }
        rows.back().immune_genotype = a.getVariable<uint64_t>("immune_genotype");
        rows.back().immune = a.getVariable<uint64_t>("immune");
        const unsigned int n_diseases = a.getVariable<unsigned int>("n_diseases");
        for (unsigned int k = 0; k < n_diseases; ++k) {  // none without disease, whose agents have no diseases array
            rows.back().diseases.push_back(a.getVariable<uint8_t, MAX_DISEASES>("diseases", k));
        }
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

// --dump-order (tests): the period's uids in turn order, the largest order key first, as "t,uid" lines.
FLAMEGPU_HOST_FUNCTION(record_order) {
    RunState& s = state();
    if (!s.order_file) {
        s.order_file = open_or_throw(s.dump_order);
        std::fputs("t,uid\n", s.order_file);
    }
    flamegpu::DeviceAgentVector pop = FLAMEGPU->agent("citizen").getPopulationData();
    std::vector<std::pair<uint64_t, unsigned int>> keyed;
    keyed.reserve(pop.size());
    for (unsigned int i = 0; i < pop.size(); ++i) {
        const auto a = pop[i];
        keyed.emplace_back((static_cast<uint64_t>(a.getVariable<unsigned int>("priority")) << 32) | a.getID(),
                           a.getVariable<unsigned int>("uid"));
    }
    std::sort(keyed.begin(), keyed.end(), [](const auto& a, const auto& b) { return a.first > b.first; });
    const unsigned int t = FLAMEGPU->getStepCounter() + 1;
    for (const auto& k : keyed) std::fprintf(s.order_file, "%u,%u\n", t, k.second);
    std::fflush(s.order_file);
}

void write_dumps(flamegpu::HostAPI* api, unsigned int t) {
    const RunState& s = state();
    if (!s.dump_at || *s.dump_at != t) return;
    if (!s.dump_agents.empty()) {
        FILE* f = open_or_throw(s.dump_agents);
        std::fprintf(f, "x,y,vision,metabolism,sugar,age,max_age,moved,neighbors,id,priority,dir_order,look_seed,"
                        "sex,fertility_start,fertility_end,initial_sugar,tags,uid,n_children,parent_a,parent_b,"
                        "n_friends,disp_x,disp_y,friends,spice,initial_spice,spice_metabolism,foresight,"
                        "immune_genotype,immune,diseases\n");
        for (const CitizenRow& a : citizens(api)) {
            std::fprintf(f, "%d,%d,%d,%d,%.17g,%d,", a.x, a.y, a.vision, a.metabolism, a.sugar, a.age);
            if (a.max_age != IMMORTAL) std::fprintf(f, "%d", a.max_age);
            std::fprintf(f, ",%u,%u,%u,%u,%u,%u,", a.moved, a.neighbors, a.id, a.priority, a.dir_order, a.look_seed);
            // Blank for no sex, as --init reads it, and Python's inf / -inf childbearing ages without sex.
            std::fprintf(f, "%s,", a.sex == SEX_F ? "F" : a.sex == SEX_M ? "M" : "");
            if (a.fertility_start != NO_FERTILITY_START) std::fprintf(f, "%d", a.fertility_start);
            std::fputc(',', f);
            if (a.fertility_end != NO_FERTILITY_END) std::fprintf(f, "%d", a.fertility_end);
            std::fprintf(f, ",%.17g,", a.initial_sugar);
            for (int i = 0; i < s.cfg.tag_length; ++i) std::fputc((a.tags >> i) & 1u ? '1' : '0', f);
            std::fprintf(f, ",%u,%u,", a.uid, a.n_children);
            if (a.parent_a != NO_UID) std::fprintf(f, "%u", a.parent_a);
            std::fputc(',', f);
            if (a.parent_b != NO_UID) std::fprintf(f, "%u", a.parent_b);
            std::fprintf(f, ",%u,%d,%d,", a.n_friends, a.disp_x, a.disp_y);
            for (unsigned int k = 0; k < a.n_friends; ++k) std::fprintf(f, "%s%u:%u", k ? "|" : "", a.friend_uid[k], a.friend_dist[k]);
            std::fprintf(f, ",%.17g,%.17g,%d,%d,", a.spice, a.initial_spice, a.spice_metabolism, a.foresight);
            // Chapter V: the immune strings, bit 0 first (empty without disease), and the canonical ids joined by '|'.
            const int bits = s.cfg.disease() ? s.cfg.immune_length : 0;
            for (int i = 0; i < bits; ++i) std::fputc((a.immune_genotype >> i) & 1u ? '1' : '0', f);
            std::fputc(',', f);
            for (int i = 0; i < bits; ++i) std::fputc((a.immune >> i) & 1u ? '1' : '0', f);
            std::fputc(',', f);
            for (size_t k = 0; k < a.diseases.size(); ++k) std::fprintf(f, "%s%u", k ? "|" : "", a.diseases[k]);
            std::fputc('\n', f);
        }
        std::fclose(f);
    }
    if (!s.dump_loans.empty()) {  // rule L's book in list order (Python's model.loans)
        FILE* f = open_or_throw(s.dump_loans);
        std::fprintf(f, "lender,borrower,principal,due,due_t\n");
        if (s.loans) {
            for (const LoanRecord& l : s.loans->to_host()) {
                std::fprintf(f, "%u,%u,%.17g,%.17g,%d\n", l.lender, l.borrower, l.principal, l.due, l.due_t);
            }
        }
        std::fclose(f);
    }
    if (!s.dump_landscape.empty()) {
        auto sugar = api->environment.getMacroProperty<float, MAX_CELLS>("sugar");
        auto pollution = api->environment.getMacroProperty<float, MAX_CELLS>("pollution");
        auto occupied = api->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
        auto spice = api->environment.getMacroProperty<float, MAX_CELLS>("spice");
        FILE* f = open_or_throw(s.dump_landscape);
        std::fprintf(f, "x,y,capacity,sugar,pollution,occupied,spice,spice_capacity\n");
        const int w = s.cfg.width, h = s.cfg.height;
        for (int x = 0; x < w; ++x) {
            for (int y = 0; y < h; ++y) {
                const unsigned int i = static_cast<unsigned int>(x + y * w);
                std::fprintf(f, "%d,%d,%u,%.17g,%.17g,%u,%.17g,%u\n", x, y, s.capacity[i],
                             static_cast<double>(static_cast<float>(sugar[i])),
                             static_cast<double>(static_cast<float>(pollution[i])), static_cast<unsigned int>(occupied[i]),
                             static_cast<double>(static_cast<float>(spice[i])), s.spice_capacity[i]);
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
        // With credit a borrower may repay down to exactly 0 at the period's end and live, as in Python, until its next
        // turn's metabolism.
        if (s.cfg.credit ? !(a.sugar >= 0.0) : !(a.sugar > 0.0f)) fail("an agent survived with sugar <= 0");
        // No such check for spice: fertility tests sugar only (p.55), so a parent may give a child more spice than it
        // holds and live, as in Python, until its next turn's metabolism.
        // Chapter V: at most one of each string of the master list, by its canonical id (Python's infect).
        if (a.diseases.size() > s.disease_bits.size()) fail("an agent carries more diseases than the master list holds");
        for (size_t k = 0; k < a.diseases.size(); ++k) {
            const unsigned int id = a.diseases[k];
            if (id >= s.disease_canon.size() || s.disease_canon[id] != id) fail("an agent carries a non-canonical disease id");
            for (size_t j = 0; j < k; ++j) {
                if (a.diseases[j] == id) fail("an agent carries one disease twice");
            }
        }
    }
    auto spice = api->environment.getMacroProperty<float, MAX_CELLS>("spice");
    unsigned long long occupied_count = 0;
    for (unsigned int i = 0; i < static_cast<unsigned int>(s.capacity.size()); ++i) {
        occupied_count += static_cast<unsigned int>(occupied[i]);
        const float v = sugar[i];
        if (!(v >= 0.0f && v <= static_cast<float>(s.capacity[i]))) fail("site sugar outside [0, capacity]");
        const float sp = spice[i];
        if (!(sp >= 0.0f && sp <= static_cast<float>(s.spice_capacity[i]))) fail("site spice outside [0, spice capacity]");
    }
    if (occupied_count != agents.size()) fail("occupied count != population");
}
