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
// the wave's number).
FLAMEGPU_AGENT_FUNCTION(run_turns, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const unsigned int row = FLAMEGPU->getVariable<unsigned int>("row");
    if (s.done[row]) return flamegpu::ALIVE;
    if (FLAMEGPU->environment.getProperty<unsigned int>("serial_turns")) {
        if (s.rank[row] != FLAMEGPU->environment.getProperty<unsigned int>("wave")) return flamegpu::ALIVE;
    } else if (s.counter[row] != 0) {
        return flamegpu::ALIVE;
    }
    take_turn(FLAMEGPU, s, row);
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

// Main model, after the turns (reads the store): the living take their state back; the starved die, each making room
// for one newcomer with replacement.
FLAMEGPU_AGENT_FUNCTION(absorb, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const unsigned int row = FLAMEGPU->getVariable<unsigned int>("row");
    if (s.dead[row]) {
        auto deaths = FLAMEGPU->environment.getMacroProperty<unsigned int>("deaths");
        ++deaths;
        if (FLAMEGPU->environment.getProperty<unsigned int>("replacement")) output_newcomer(FLAMEGPU, starved_key(s.rank[row]));
        return flamegpu::DEAD;
    }
    FLAMEGPU->setVariable<int>("x", s.x[row]);
    FLAMEGPU->setVariable<int>("y", s.y[row]);
    FLAMEGPU->setVariable<int>("disp_x", s.disp_x[row]);
    FLAMEGPU->setVariable<int>("disp_y", s.disp_y[row]);
    FLAMEGPU->setVariable<double>("sugar", s.sugar[row]);
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

// Main model, after absorb (reads the store): each site's newborn becomes a citizen, created by the site's cell.
FLAMEGPU_AGENT_FUNCTION(spawn_newborns, flamegpu::MessageNone, flamegpu::MessageNone) {
    const Store& s = the_store(FLAMEGPU);
    const int c = s.site_row[FLAMEGPU->getIndex()];  // the site index (make_cells)
    if (c < static_cast<int>(s.n_rows)) return flamegpu::ALIVE;
    auto& out = FLAMEGPU->agent_out;
    out.setVariable<int>("x", s.x[c]);
    out.setVariable<int>("y", s.y[c]);
    out.setVariable<int>("vision", s.vision[c]);
    out.setVariable<int>("metabolism", s.metabolism[c]);
    out.setVariable<int>("age", s.age[c]);
    out.setVariable<int>("max_age", s.max_age[c]);
    out.setVariable<double>("sugar", s.sugar[c]);
    out.setVariable<double>("initial_sugar", s.initial_sugar[c]);
    out.setVariable<unsigned int>("uid", s.uid[c]);
    out.setVariable<unsigned int>("sex", s.sex[c]);
    out.setVariable<int>("fertility_start", s.fertility_start[c]);
    out.setVariable<int>("fertility_end", s.fertility_end[c]);
    out.setVariable<uint64_t>("tags", s.tags[c]);
    out.setVariable<unsigned int>("parent_a", s.parent_a[c]);
    out.setVariable<unsigned int>("parent_b", s.parent_b[c]);
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
        output_newcomer(FLAMEGPU, old_age_key(FLAMEGPU->getVariable<unsigned int>("uid")));
    }
    return flamegpu::DEAD;
}

// Newcomers' uids in Python's creation order (store.h, NewcomerUids): post the death key, then take the uid.
FLAMEGPU_AGENT_FUNCTION(newcomer_post, flamegpu::MessageNone, flamegpu::MessageNone) {
    if (FLAMEGPU->getVariable<int>("x") >= 0) return flamegpu::ALIVE;
    const NewcomerSlots& n = *reinterpret_cast<const NewcomerSlots*>(FLAMEGPU->environment.getProperty<uint64_t>("newcomers"));
    const unsigned int slot = atomicAdd(n.count, 1u);
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
