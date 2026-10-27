// The turns' agent functions (spec 2026-10-25-gpu-full-parity, sections 1 and 2): publish the citizens into the
// store, run every turn in the period's order in waves (the turns sub-model), absorb the store back, then old age.
// Included only by model.cu.
#ifndef SRC_TURNS_CUH_
#define SRC_TURNS_CUH_

#include <string>

#include "host_state.h"
#include "rules.cuh"
#include "store.h"
#include "turn.cuh"

template <typename API>
__device__ __forceinline__ const Store& the_store(API* FLAMEGPU) {
    return *reinterpret_cast<const Store*>(FLAMEGPU->environment.template getProperty<uint64_t>("store"));
}

// Main model, after movement (reads the citizen's variables; writes the store): each citizen's row is its index now.
FLAMEGPU_AGENT_FUNCTION(publish, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const unsigned int row = FLAMEGPU->getIndex();
    FLAMEGPU->setVariable<unsigned int>("row", row);
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    const int x = FLAMEGPU->getVariable<int>("x"), y = FLAMEGPU->getVariable<int>("y");
    const unsigned int start = static_cast<unsigned int>(x) + static_cast<unsigned int>(y) * w;
    const bool moving = FLAMEGPU->getVariable<unsigned int>("settled") == MOVE_HOLD;
    const unsigned int target = moving ? FLAMEGPU->getVariable<unsigned int>("target") : start;
    s.start[row] = start;
    s.target[row] = target;
    s.key[row] = order_key(FLAMEGPU->getVariable<unsigned int>("priority"), FLAMEGPU->getID());
    s.x[row] = x;
    s.y[row] = y;
    s.vision[row] = FLAMEGPU->getVariable<int>("vision");
    s.metabolism[row] = FLAMEGPU->getVariable<int>("metabolism");
    s.age[row] = FLAMEGPU->getVariable<int>("age");
    s.max_age[row] = FLAMEGPU->getVariable<int>("max_age");
    s.fertility_start[row] = FLAMEGPU->getVariable<int>("fertility_start");
    s.fertility_end[row] = FLAMEGPU->getVariable<int>("fertility_end");
    s.disp_x[row] = FLAMEGPU->getVariable<int>("disp_x");
    s.disp_y[row] = FLAMEGPU->getVariable<int>("disp_y");
    s.sugar[row] = FLAMEGPU->getVariable<double>("sugar");
    s.initial_sugar[row] = FLAMEGPU->getVariable<double>("initial_sugar");
    s.spice[row] = FLAMEGPU->getVariable<double>("spice");
    s.initial_spice[row] = FLAMEGPU->getVariable<double>("initial_spice");
    s.spice_metabolism[row] = FLAMEGPU->getVariable<int>("spice_metabolism");
    s.foresight[row] = FLAMEGPU->getVariable<int>("foresight");
    s.tags[row] = FLAMEGPU->getVariable<uint64_t>("tags");
    const unsigned int uid = FLAMEGPU->getVariable<unsigned int>("uid");
    s.uid[row] = uid;
    s.sex[row] = FLAMEGPU->getVariable<unsigned int>("sex");
    s.n_children[row] = FLAMEGPU->getVariable<unsigned int>("n_children");
    s.parent_a[row] = FLAMEGPU->getVariable<unsigned int>("parent_a");
    s.parent_b[row] = FLAMEGPU->getVariable<unsigned int>("parent_b");
    s.n_friends[row] = FLAMEGPU->getVariable<unsigned int>("n_friends");
    for (unsigned int f = 0; f < MAX_FRIENDS; ++f) {
        s.friend_uid[row * MAX_FRIENDS + f] = FLAMEGPU->getVariable<unsigned int, MAX_FRIENDS>("friend_uid", f);
        s.friend_dist[row * MAX_FRIENDS + f] = FLAMEGPU->getVariable<unsigned int, MAX_FRIENDS>("friend_dist", f);
    }
    s.look_seed[row] = FLAMEGPU->getVariable<unsigned int>("look_seed");
    s.dir_order[row] = FLAMEGPU->getVariable<unsigned int>("dir_order");
    s.moved[row] = 0u;
    s.neighbors[row] = 0u;
    s.dead[row] = 0u;
    s.site_row[start] = static_cast<int>(row);
    if (moving) s.target_row[target] = static_cast<int>(row);
    if (uid < s.uid_capacity) {
        s.uid_row[uid] = static_cast<int>(row);
    } else {
        atomicOr(s.errors, STORE_UID_CAPACITY);
    }
    return flamegpu::ALIVE;
}

// Turns sub-model, layer A: a turn whose waits are over takes its turn (in serial mode, only the turn whose rank is
// the wave's number). A combat victim killed earlier in the period takes no turn, but still releases those after it.
FLAMEGPU_AGENT_FUNCTION(run_turns, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const unsigned int row = FLAMEGPU->getVariable<unsigned int>("row");
    if (s.done[row]) return flamegpu::ALIVE;
    if (FLAMEGPU->environment.getProperty<unsigned int>("serial_turns")) {
        if (s.rank[row] != FLAMEGPU->environment.getProperty<unsigned int>("wave")) return flamegpu::ALIVE;
    } else if (s.counter[row] != 0) {
        return flamegpu::ALIVE;
    }
    if (!s.dead[row]) take_turn(FLAMEGPU, s, row);
    s.done[row] = 1u;
    s.ran[row] = 1u;
    atomicAdd(s.ran_count, 1u);
    atomicAdd(s.done_count, 1u);
    return flamegpu::ALIVE;
}

// Turns sub-model, layer B: a turn that ran this wave releases the group after each of its entries.
FLAMEGPU_AGENT_FUNCTION(release_turns, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const unsigned int row = FLAMEGPU->getVariable<unsigned int>("row");
    if (!s.ran[row]) return flamegpu::ALIVE;
    s.ran[row] = 0u;
    const unsigned int first = s.fp_offset[row], end = first + s.fp_count[row];
    for (unsigned int e = first; e < end; ++e) {
        const int u = s.entry_pos[e];
        if (u < 0) continue;  // a duplicate of another of this turn's entries
        const unsigned int next = s.entry_group[u] + 1u;
        if (s.group_site[next] != static_cast<unsigned int>(s.unique_key[u] >> 32)) continue;  // the site's last group
        for (unsigned int j = s.group_first[next]; j < s.group_first[next + 1]; ++j) {
            atomicSub(&s.counter[s.rank_row[static_cast<unsigned int>(s.unique_key[j])]], 1);
        }
    }
    return flamegpu::ALIVE;
}

// Main model, after the turns (reads the store): the living take their state back; the starved and combat's victims
// die, each making room for one newcomer with replacement, in the order of their deaths (turn_death_key).
FLAMEGPU_AGENT_FUNCTION(absorb, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const unsigned int row = FLAMEGPU->getVariable<unsigned int>("row");
    if (s.dead[row]) {
        auto deaths = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
        ++deaths;
        if (FLAMEGPU->environment.getProperty<unsigned int>("replacement")) {
            output_newcomer(FLAMEGPU, s.death_key[row], s.tags[row]);
        }
        return flamegpu::DEAD;
    }
    FLAMEGPU->setVariable<int>("x", s.x[row]);
    FLAMEGPU->setVariable<int>("y", s.y[row]);
    FLAMEGPU->setVariable<int>("disp_x", s.disp_x[row]);
    FLAMEGPU->setVariable<int>("disp_y", s.disp_y[row]);
    FLAMEGPU->setVariable<double>("sugar", s.sugar[row]);
    FLAMEGPU->setVariable<double>("spice", s.spice[row]);
    FLAMEGPU->setVariable<uint64_t>("tags", s.tags[row]);
    FLAMEGPU->setVariable<unsigned int>("n_children", s.n_children[row]);
    FLAMEGPU->setVariable<unsigned int>("n_friends", s.n_friends[row]);
    for (unsigned int f = 0; f < MAX_FRIENDS; ++f) {
        FLAMEGPU->setVariable<unsigned int, MAX_FRIENDS>("friend_uid", f, s.friend_uid[row * MAX_FRIENDS + f]);
        FLAMEGPU->setVariable<unsigned int, MAX_FRIENDS>("friend_dist", f, s.friend_dist[row * MAX_FRIENDS + f]);
    }
    FLAMEGPU->setVariable<unsigned int>("moved", s.moved[row]);
    FLAMEGPU->setVariable<unsigned int>("neighbors", s.neighbors[row]);
    return flamegpu::ALIVE;
}

// Main model, cell layers around the turns: during the turns the sites' sugar lives in the store, so a combat turn can
// read a site's sugar while other turns harvest (a macro property may not be read and written in one layer).
FLAMEGPU_AGENT_FUNCTION(stage_sites, flamegpu::MessageNone, flamegpu::MessageNone) {  // reads sugar, spice
    const unsigned int c = FLAMEGPU->getIndex();  // the site index (make_cells)
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    the_store(FLAMEGPU).site_sugar[c] = sugar[c];
    if (FLAMEGPU->environment.getProperty<unsigned int>("spice")) {
        auto spice = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("spice");
        the_store(FLAMEGPU).site_spice[c] = spice[c];
    }
    return flamegpu::ALIVE;
}

FLAMEGPU_AGENT_FUNCTION(unstage_sites, flamegpu::MessageNone, flamegpu::MessageNone) {  // writes sugar, spice
    const unsigned int c = FLAMEGPU->getIndex();
    auto sugar = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("sugar");
    sugar[c].exchange(the_store(FLAMEGPU).site_sugar[c]);
    if (FLAMEGPU->environment.getProperty<unsigned int>("spice")) {
        auto spice = FLAMEGPU->environment.getMacroProperty<float, MAX_CELLS>("spice");
        spice[c].exchange(the_store(FLAMEGPU).site_spice[c]);
    }
    return flamegpu::ALIVE;
}

// Main model, after absorb (reads the store): each site's newborn becomes a citizen, created by the site's cell.
FLAMEGPU_AGENT_FUNCTION(spawn_newborns, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const int c = s.site_row[FLAMEGPU->getIndex()];  // the site index (make_cells)
    if (c < static_cast<int>(s.n_rows)) return flamegpu::ALIVE;
    init_citizen_out(FLAMEGPU);
    auto& out = FLAMEGPU->agent_out;
    out.setVariable<int>("x", s.x[c]);
    out.setVariable<int>("y", s.y[c]);
    out.setVariable<int>("vision", s.vision[c]);
    out.setVariable<int>("metabolism", s.metabolism[c]);
    out.setVariable<int>("age", s.age[c]);
    out.setVariable<int>("max_age", s.max_age[c]);
    out.setVariable<double>("sugar", s.sugar[c]);
    out.setVariable<double>("initial_sugar", s.initial_sugar[c]);
    out.setVariable<double>("spice", s.spice[c]);
    out.setVariable<double>("initial_spice", s.initial_spice[c]);
    out.setVariable<int>("spice_metabolism", s.spice_metabolism[c]);
    out.setVariable<int>("foresight", s.foresight[c]);
    out.setVariable<unsigned int>("uid", s.uid[c]);
    out.setVariable<unsigned int>("sex", s.sex[c]);
    out.setVariable<int>("fertility_start", s.fertility_start[c]);
    out.setVariable<int>("fertility_end", s.fertility_end[c]);
    out.setVariable<uint64_t>("tags", s.tags[c]);
    out.setVariable<unsigned int>("parent_a", s.parent_a[c]);
    out.setVariable<unsigned int>("parent_b", s.parent_b[c]);
    out.setVariable<unsigned int>("n_children", s.n_children[c]);  // a newborn may already be a parent (fertility from 0)
    return flamegpu::ALIVE;
}

// Main model, end of the period (writes occupied, deaths): every citizen ages; those at their maximum age die, each
// making room for one newcomer with replacement. This period's newcomers (unplaced) are left for next period, as
// Python spawns them after aging.
FLAMEGPU_AGENT_FUNCTION(age_and_die, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<int>("x") < 0) return flamegpu::ALIVE;
    const int age = FLAMEGPU->getVariable<int>("age") + 1;
    FLAMEGPU->setVariable<int>("age", age);
    if (age < FLAMEGPU->getVariable<int>("max_age")) return flamegpu::ALIVE;
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    occupied[static_cast<unsigned int>(FLAMEGPU->getVariable<int>("x")) +
             static_cast<unsigned int>(FLAMEGPU->getVariable<int>("y")) * w].exchange(0u);
    auto deaths = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
    ++deaths;
    if (FLAMEGPU->environment.getProperty<unsigned int>("replacement")) {
        output_newcomer(FLAMEGPU, old_age_key(FLAMEGPU->getVariable<unsigned int>("uid")),
                        FLAMEGPU->getVariable<uint64_t>("tags"));
    }
    return flamegpu::DEAD;
}

// Rule I at old age (spec section 4; store.h, DyingTable), end of the period with inheritance on, in place of
// age_and_die: everyone ages and the dying post themselves; heirs count themselves, then take their parents' shares in
// the parents' creation order (Python processes the dying batch in agents-list order); then the dying die.
template <typename API>
__device__ __forceinline__ const Dying& the_dying(API* FLAMEGPU) {
    return *reinterpret_cast<const Dying*>(FLAMEGPU->environment.template getProperty<uint64_t>("dying"));
}

FLAMEGPU_AGENT_FUNCTION(age_mark, flamegpu::MessageNone, flamegpu::MessageNone) {
    FLAMEGPU->setVariable<unsigned int>("dying", 0u);
    if (FLAMEGPU->getVariable<int>("x") < 0) return flamegpu::ALIVE;  // this period's newcomers
    const int age = FLAMEGPU->getVariable<int>("age") + 1;
    FLAMEGPU->setVariable<int>("age", age);
    if (age < FLAMEGPU->getVariable<int>("max_age")) return flamegpu::ALIVE;
    FLAMEGPU->setVariable<unsigned int>("dying", 1u);
    const Dying& d = the_dying(FLAMEGPU);
    const unsigned int slot = atomicAdd(d.count, 1u);
    d.uid[slot] = FLAMEGPU->getVariable<unsigned int>("uid");
    d.sugar[slot] = FLAMEGPU->getVariable<double>("sugar");
    d.spice[slot] = FLAMEGPU->getVariable<double>("spice");
    return flamegpu::ALIVE;
}

FLAMEGPU_AGENT_FUNCTION(heirs_count, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<int>("x") < 0 || FLAMEGPU->getVariable<unsigned int>("dying")) return flamegpu::ALIVE;
    const Dying& d = the_dying(FLAMEGPU);
    const unsigned int parents[2] = {FLAMEGPU->getVariable<unsigned int>("parent_a"),
                                     FLAMEGPU->getVariable<unsigned int>("parent_b")};
    for (const unsigned int p : parents) {
        const int e = p == NO_UID ? -1 : find_dying(d, p);
        if (e >= 0) atomicAdd(&d.heirs[e], 1u);
    }
    return flamegpu::ALIVE;
}

FLAMEGPU_AGENT_FUNCTION(heirs_take, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<int>("x") < 0 || FLAMEGPU->getVariable<unsigned int>("dying")) return flamegpu::ALIVE;
    const Dying& d = the_dying(FLAMEGPU);
    const unsigned int a = FLAMEGPU->getVariable<unsigned int>("parent_a");
    const unsigned int b = FLAMEGPU->getVariable<unsigned int>("parent_b");
    const unsigned int first = a < b ? a : b, second = a < b ? b : a;  // NO_UID is the largest, so last
    double sugar = FLAMEGPU->getVariable<double>("sugar"), spice = FLAMEGPU->getVariable<double>("spice");
    for (const unsigned int p : {first, second}) {
        const int e = p == NO_UID ? -1 : find_dying(d, p);
        if (e >= 0 && d.sugar[e] > 0.0) sugar += d.sugar[e] / static_cast<double>(d.heirs[e]);
        if (e >= 0 && d.spice[e] > 0.0) spice += d.spice[e] / static_cast<double>(d.heirs[e]);
    }
    FLAMEGPU->setVariable<double>("sugar", sugar);
    FLAMEGPU->setVariable<double>("spice", spice);
    return flamegpu::ALIVE;
}

FLAMEGPU_AGENT_FUNCTION(die_old, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (!FLAMEGPU->getVariable<unsigned int>("dying")) return flamegpu::ALIVE;
    const unsigned int w = FLAMEGPU->environment.getProperty<unsigned int>("width");
    auto occupied = FLAMEGPU->environment.getMacroProperty<unsigned int, MAX_CELLS>("occupied");
    occupied[static_cast<unsigned int>(FLAMEGPU->getVariable<int>("x")) +
             static_cast<unsigned int>(FLAMEGPU->getVariable<int>("y")) * w].exchange(0u);
    auto deaths = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
    ++deaths;
    if (FLAMEGPU->environment.getProperty<unsigned int>("replacement")) {
        output_newcomer(FLAMEGPU, old_age_key(FLAMEGPU->getVariable<unsigned int>("uid")),
                        FLAMEGPU->getVariable<uint64_t>("tags"));
    }
    return flamegpu::DEAD;
}

FLAMEGPU_HOST_FUNCTION(dying_posting) { state().dying->posting(); }
FLAMEGPU_HOST_FUNCTION(dying_sort) { state().dying->sort(); }

// Newcomers' uids in Python's creation order (store.h, NewcomerUids): post the death key, then take the uid.
FLAMEGPU_AGENT_FUNCTION(newcomer_post, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<int>("x") >= 0) return flamegpu::ALIVE;
    const NewcomerSlots& n = *reinterpret_cast<const NewcomerSlots*>(FLAMEGPU->environment.getProperty<uint64_t>("newcomers"));
    const unsigned int slot = atomicAdd(n.count, 1u);
    if (slot >= n.capacity) return flamegpu::ALIVE;  // NewcomerUids::assign() names the limit
    n.key[slot] = FLAMEGPU->getVariable<uint64_t>("death_key");
    n.slot[slot] = slot;
    FLAMEGPU->setVariable<unsigned int>("nc_slot", slot);
    return flamegpu::ALIVE;
}

FLAMEGPU_AGENT_FUNCTION(newcomer_take, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<int>("x") >= 0) return flamegpu::ALIVE;
    const NewcomerSlots& n = *reinterpret_cast<const NewcomerSlots*>(FLAMEGPU->environment.getProperty<uint64_t>("newcomers"));
    FLAMEGPU->setVariable<unsigned int>("uid", n.uid[FLAMEGPU->getVariable<unsigned int>("nc_slot")]);
    return flamegpu::ALIVE;
}

// Host layers around the turns.
FLAMEGPU_HOST_FUNCTION(prepare_turns) {
    RunState& s = state();
    s.turn_rows = FLAMEGPU->agent("citizen").count();
    s.store->prepare(s.turn_rows);
}

FLAMEGPU_HOST_FUNCTION(schedule_turns) {
    RunState& s = state();
    s.store->schedule(s.turn_rows, s.cfg);
    FLAMEGPU->environment.setProperty<unsigned int>("wave", 0u);
    s.waves_this_period = 0;
}

// Another wave while turns are pending; a wave that ran none would never end (spec section 2, anti-goal "no hang").
FLAMEGPU_EXIT_CONDITION(turns_done) {
    RunState& s = state();
    unsigned int ran = 0, done = 0;
    s.store->wave_counts(&ran, &done);
    ++s.waves_this_period;
    if (done >= s.turn_rows) return flamegpu::EXIT;
    if (ran == 0) {
        throw SchedulerError("a wave ran no turn with " + std::to_string(s.turn_rows - done) + " turns pending");
    }
    FLAMEGPU->environment.setProperty<unsigned int>("wave", FLAMEGPU->environment.getProperty<unsigned int>("wave") + 1);
    return flamegpu::CONTINUE;
}

// After the turns: the period's newborns take uids in creation order (Python's new_agent ids).
FLAMEGPU_HOST_FUNCTION(assign_births) {
    RunState& s = state();
    if (s.check) {  // every site a turn touched was in its footprint (store.h, touch())
        const auto miss = s.store->footprint_misses();
        if (miss[0]) {
            throw InvariantError("t=" + std::to_string(FLAMEGPU->getStepCounter() + 1) + ": " + std::to_string(miss[0]) +
                                 " sites touched outside a turn's footprint; the first: site " + std::to_string(miss[1]) +
                                 " by the turn of rank " + std::to_string(miss[2]) + " at touch point " +
                                 std::to_string(miss[3]));
        }
    }
    s.newborns_this_period = s.store->birth_uids(s.next_uid);
    s.next_uid += s.newborns_this_period;
    if (s.next_uid > s.cfg.uid_capacity) {
        throw CapacityError("uid capacity " + std::to_string(s.cfg.uid_capacity) +
                            " exceeded: more agents created than --uid-capacity allows");
    }
}

// After the turns, with rule T: the period's exchanges for the metrics row (StoreHost::trade_totals).
FLAMEGPU_HOST_FUNCTION(total_trades) { state().trades = state().store->trade_totals(); }

// After the turns: a newborn that combat killed in its birth period is a death, as Python's die() makes it (its uid
// came with the others in assign_births). It is no citizen, so it is never spawned; the host lists and counts it, and
// with replacement cell i makes the i-th one's newcomer (replace_newborns), unplaced and with the victim's death key so
// newcomer_post orders it among the period's deaths.
FLAMEGPU_HOST_FUNCTION(bury_newborns) {
    const unsigned int buried = state().store->bury();
    if (!buried) return;
    auto deaths = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
    deaths += buried;
}

FLAMEGPU_AGENT_FUNCTION(replace_newborns, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const unsigned int i = FLAMEGPU->getIndex();
    if (i < s.n_buried) output_newcomer(FLAMEGPU, s.buried_key[i], s.buried_tags[i]);
    return flamegpu::ALIVE;
}

// R's newcomers take uids after the period's newborns, in the order of their deaths.
FLAMEGPU_HOST_FUNCTION(assign_newcomers) {
    RunState& s = state();
    s.next_uid += s.newcomers->assign(s.next_uid);
    if (s.next_uid > s.cfg.uid_capacity) {
        throw CapacityError("uid capacity " + std::to_string(s.cfg.uid_capacity) +
                            " exceeded: more agents created than --uid-capacity allows");
    }
}

#endif  // SRC_TURNS_CUH_
