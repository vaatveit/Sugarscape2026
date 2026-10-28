#include "model.h"

#include <array>
#include <memory>

#include "host_state.h"
#include "movement.cuh"
#include "rules.cuh"
#include "turns.cuh"

namespace {

// Chapter V's switches and the master list (RunState's disease_bits and disease_len; host_state.cu,
// make_disease_list), in the main and turns models.
void disease_properties(flamegpu::EnvironmentDescription env, const RunConfig& cfg) {
    const RunState& s = state();
    std::array<uint64_t, MAX_DISEASES> bits{};
    std::array<unsigned int, MAX_DISEASES> len{};
    for (size_t i = 0; i < s.disease_bits.size(); ++i) {
        bits[i] = s.disease_bits[i];
        len[i] = s.disease_len[i];
    }
    env.newProperty<unsigned int>("disease", cfg.disease() ? 1u : 0u);
    env.newProperty<unsigned int>("immune_length", static_cast<unsigned int>(cfg.immune_length));
    env.newProperty<double>("disease_fee", cfg.disease() ? cfg.disease_fee : 0.0);  // Python's Agent.disease_fee
    env.newProperty<uint64_t, MAX_DISEASES>("disease_bits", bits);
    env.newProperty<unsigned int, MAX_DISEASES>("disease_len", len);
}

void landscape_macros(flamegpu::EnvironmentDescription env, bool all) {
    env.newMacroProperty<unsigned int, MAX_CELLS>("occupied");
    env.newMacroProperty<float, MAX_CELLS>("sugar");
    env.newMacroProperty<float, MAX_CELLS>("pollution");
    env.newMacroProperty<uint64_t, MAX_CELLS>("claim");
    env.newMacroProperty<float, MAX_CELLS>("spice");  // the second commodity (p.96); 0 everywhere without spice
    if (!all) return;
    env.newMacroProperty<float, MAX_CELLS>("sugar_next");
    env.newMacroProperty<float, MAX_CELLS>("pollution_next");
    env.newMacroProperty<float, MAX_CELLS>("spice_next");
    env.newMacroProperty<unsigned int>("deaths");
    // The period's order key of the agent that started at a site and of the one that ended there and has not starved,
    // for count_neighbors (spec 2026-10-25-gpu-sequential-semantics, section 3); cleared in cell_commit.
    env.newMacroProperty<uint64_t, MAX_CELLS>("left");
    env.newMacroProperty<uint64_t, MAX_CELLS>("arrived");
}

// The movement sub-model: propose and bid until a round places no bid (spec 2026-10-25-gpu-sequential-semantics,
// section 2); commit_move then moves everyone at once.
void describe_movement(flamegpu::ModelDescription& sub, const RunConfig& cfg) {
    flamegpu::EnvironmentDescription env = sub.Environment();
    env.newProperty<unsigned int>("width", cfg.width);
    env.newProperty<unsigned int>("height", cfg.height);
    env.newProperty<unsigned int>("round", 1u);
    env.newProperty<unsigned int>("pollution_active", 0u);
    env.newProperty<float>("pollution_alpha", 0.0f);
    env.newProperty<unsigned int>("look_stride", 1u);
    // Welfare movement with spice (movement.cuh, propose); the parent model's values reach these through the
    // sub-environment.
    env.newProperty<unsigned int>("spice", 0u);
    env.newProperty<unsigned int>("cultural_preferences", 0u);
    env.newProperty<unsigned int>("tag_length", 0u);
    env.newProperty<double>("disease_fee", 0.0);  // Chapter V: the fee counts in welfare (movement.cuh, propose)
    landscape_macros(env, false);
    flamegpu::AgentDescription citizen = sub.newAgent("citizen");
    citizen.newVariable<unsigned int>("look_seed");
    citizen.newVariable<unsigned int>("dir_order");
    citizen.newVariable<int>("x");
    citizen.newVariable<int>("y");
    citizen.newVariable<int>("vision");
    citizen.newVariable<double>("sugar");
    citizen.newVariable<double>("spice");
    citizen.newVariable<int>("metabolism");
    citizen.newVariable<int>("spice_metabolism");
    citizen.newVariable<int>("foresight");
    citizen.newVariable<uint64_t>("tags");
    citizen.newVariable<unsigned int>("n_diseases");  // the disease fee in welfare (Chapter V)
    citizen.newVariable<unsigned int>("moved");
    citizen.newVariable<unsigned int>("settled");
    citizen.newVariable<unsigned int>("priority");
    citizen.newVariable<unsigned int>("target");
    env.newMacroProperty<unsigned int>("bids");  // bids placed this round (bid; movement_settled)
    sub.newLayer().addAgentFunction(citizen.newFunction("propose", propose));
    sub.newLayer().addAgentFunction(citizen.newFunction("bid", bid));
    sub.addExitCondition(movement_settled);
}

// The pollution_diffusion sub-model: D's passes after the first (rules.cuh, diffuse).
void describe_diffusion(flamegpu::ModelDescription& sub, const RunConfig& cfg) {
    flamegpu::EnvironmentDescription env = sub.Environment();
    env.newProperty<unsigned int>("width", cfg.width);
    env.newProperty<unsigned int>("height", cfg.height);
    env.newProperty<unsigned int>("extra_passes", 0u);
    env.newProperty<unsigned int>("diffusion_pass", 0u);
    env.newMacroProperty<float, MAX_CELLS>("pollution");
    env.newMacroProperty<float, MAX_CELLS>("pollution_next");
    flamegpu::AgentDescription cell = sub.newAgent("cell");
    sub.newLayer().addAgentFunction(cell.newFunction("diffuse", diffuse));
    sub.newLayer().addAgentFunction(cell.newFunction("diffuse_commit", diffuse_commit));
    sub.addExitCondition(diffusion_done);
}

// The turns sub-model: waves of run_turns and release_turns until every turn has run (turns.cuh, turns_done).
void describe_turns(flamegpu::ModelDescription& sub, const RunConfig& cfg) {
    flamegpu::EnvironmentDescription env = sub.Environment();
    env.newProperty<unsigned int>("width", cfg.width);
    env.newProperty<unsigned int>("height", cfg.height);
    env.newProperty<unsigned int>("pollution_active", 0u);
    env.newProperty<float>("pollution_alpha", 0.0f);
    env.newProperty<float>("pollution_beta", 0.0f);
    env.newProperty<uint64_t>("store", 0);
    env.newProperty<unsigned int>("serial_turns", 0u);
    env.newProperty<unsigned int>("wave", 0u);
    env.newProperty<unsigned int>("look_stride", 1u);
    // Rule S (sex.cuh); the parent model's values reach these through the sub-environment.
    env.newProperty<unsigned int>("sex", 0u);
    env.newProperty<unsigned int>("culture", 0u);
    env.newProperty<unsigned int>("tag_length", 0u);
    for (const char* name : {"mate_vision", "child_capped", "child_redraw", "gift_down"}) env.newProperty<unsigned int>(name, 0u);
    env.newProperty<double>("fertility_threshold", 1.0);
    env.newProperty<double>("child_share", 0.5);
    env.newProperty<unsigned int>("combat", 0u);  // combat C_alpha replaces the move (combat.cuh)
    env.newProperty<double>("combat_alpha", 0.0);
    env.newProperty<unsigned int>("inheritance", 0u);  // rule I for deaths in a turn (heirs.cuh, pay_heirs)
    // Chapter IV in the turn: spice, and rule S's redrawn initial spice (sex.cuh); rule T (trade.cuh).
    env.newProperty<unsigned int>("spice", 0u);
    env.newProperty<unsigned int>("trade", 0u);
    env.newProperty<unsigned int>("trade_down", 0u);
    env.newProperty<unsigned int>("cultural_preferences", 0u);
    env.newProperty<unsigned int>("credit", 0u);  // rule L (credit.cuh)
    env.newProperty<int>("credit_duration", 0);
    env.newProperty<double>("credit_rate", 0.0);
    env.newProperty<unsigned int>("t", 0u);  // Python's Model.t: with inheritance, loans join the book in the turn
    disease_properties(env, cfg);  // Chapter V: rule S crosses the immune genotypes; rule E (disease.cuh)
    env.newProperty<int>("spice_endowment_lo", 0);
    env.newProperty<int>("spice_endowment_hi", 0);
    for (const char* name : {"endowment_lo", "endowment_hi", "fertility_start_lo", "fertility_start_hi",
                             "female_fertility_end_lo", "female_fertility_end_hi", "male_fertility_end_lo",
                             "male_fertility_end_hi"}) {
        env.newProperty<int>(name, 0);
    }
    // The sites' sugar is the store's during the turns (turns.cuh, stage_sites).
    env.newMacroProperty<unsigned int, MAX_CELLS>("occupied");
    env.newMacroProperty<float, MAX_CELLS>("pollution");
    flamegpu::AgentDescription citizen = sub.newAgent("citizen");
    citizen.newVariable<unsigned int>("row");
    sub.newLayer().addAgentFunction(citizen.newFunction("run_turns", run_turns));
    sub.newLayer().addAgentFunction(citizen.newFunction("release_turns", release_turns));
    sub.addExitCondition(turns_done);
}

}  // namespace

void describe_model(flamegpu::ModelDescription& model, const RunConfig& cfg) {
    flamegpu::EnvironmentDescription env = model.Environment();
    env.newProperty<unsigned int>("width", cfg.width);
    env.newProperty<unsigned int>("height", cfg.height);
    env.newProperty<float>("growback_rate", static_cast<float>(cfg.growback_rate));
    env.newProperty<float>("pollution_alpha", cfg.pollution ? static_cast<float>(cfg.pollution->first) : 0.0f);
    env.newProperty<float>("pollution_beta", cfg.pollution ? static_cast<float>(cfg.pollution->second) : 0.0f);
    env.newProperty<unsigned int>("pollution_active", 0u);
    env.newProperty<unsigned int>("diffuse_now", 0u);
    env.newProperty<unsigned int>("extra_passes", 0u);    // D's passes after the first this period
    env.newProperty<unsigned int>("diffusion_pass", 0u);  // extra passes done so far this period
    env.newProperty<unsigned int>("initialising", 0u);    // 1 in the first period only: cell_initialise runs
    env.newProperty<unsigned int>("look_stride", static_cast<unsigned int>(cfg.look_stride));
    // R's newcomers (rules.cuh, output_newcomer): their draws' inclusive ranges.
    env.newProperty<unsigned int>("replacement", cfg.replacement ? 1u : 0u);
    env.newProperty<unsigned int>("same_tribe", cfg.replacement_same_tribe ? 1u : 0u);  // newcomers of the dead's tribe
    env.newProperty<int>("vision_lo", cfg.vision.lo);
    env.newProperty<int>("vision_hi", cfg.vision.hi);
    env.newProperty<int>("metabolism_lo", cfg.metabolism.lo);
    env.newProperty<int>("metabolism_hi", cfg.metabolism.hi);
    env.newProperty<int>("endowment_lo", cfg.endowment.lo);
    env.newProperty<int>("endowment_hi", cfg.endowment.hi);
    env.newProperty<int>("max_age_lo", cfg.max_age ? cfg.max_age->lo : 0);
    env.newProperty<int>("max_age_hi", cfg.max_age ? cfg.max_age->hi : 0);
    // Chapter III draws for newcomers (rules.cuh, output_newcomer).
    env.newProperty<unsigned int>("tag_length", static_cast<unsigned int>(cfg.tag_length));
    env.newProperty<unsigned int>("sex", cfg.sex ? 1u : 0u);
    env.newProperty<int>("fertility_start_lo", cfg.fertility_start.lo);
    env.newProperty<int>("fertility_start_hi", cfg.fertility_start.hi);
    env.newProperty<int>("female_fertility_end_lo", cfg.female_fertility_end.lo);
    env.newProperty<int>("female_fertility_end_hi", cfg.female_fertility_end.hi);
    env.newProperty<int>("male_fertility_end_lo", cfg.male_fertility_end.lo);
    env.newProperty<int>("male_fertility_end_hi", cfg.male_fertility_end.hi);
    env.newProperty<unsigned int>("culture", cfg.culture ? 1u : 0u);  // rule K and friends (culture.cuh)
    // Rule S's options (sex.cuh).
    env.newProperty<unsigned int>("mate_vision", cfg.mate_contact == "vision" ? 1u : 0u);
    env.newProperty<unsigned int>("child_capped", cfg.child_gift == "capped" ? 1u : 0u);
    env.newProperty<unsigned int>("child_redraw", cfg.child_threshold == "redraw" ? 1u : 0u);
    env.newProperty<unsigned int>("gift_down", cfg.gift_rounding == "down" ? 1u : 0u);
    env.newProperty<double>("fertility_threshold", cfg.fertility_threshold);
    env.newProperty<double>("child_share", cfg.child_share);
    // Combat C_alpha (combat.cuh); INFINITY is C_inf.
    env.newProperty<unsigned int>("combat", cfg.combat() ? 1u : 0u);
    env.newProperty<double>("combat_alpha", cfg.combat() ? *cfg.combat_alpha : 0.0);
    env.newProperty<unsigned int>("inheritance", cfg.inheritance ? 1u : 0u);
    // Chapter IV (plan 2026-10-26-gpu-parity-part-c): spice, and newcomers' Chapter IV draws (rules.cuh,
    // output_newcomer).
    env.newProperty<unsigned int>("spice", cfg.spice ? 1u : 0u);
    env.newProperty<int>("spice_metabolism_lo", cfg.spice_metabolism.lo);
    env.newProperty<int>("spice_metabolism_hi", cfg.spice_metabolism.hi);
    const IntRange spice_endowment = cfg.spice_endowment.value_or(cfg.endowment);
    env.newProperty<int>("spice_endowment_lo", spice_endowment.lo);
    env.newProperty<int>("spice_endowment_hi", spice_endowment.hi);
    env.newProperty<unsigned int>("foresight_on", cfg.foresight ? 1u : 0u);
    env.newProperty<int>("foresight_lo", cfg.foresight ? cfg.foresight->lo : 0);
    env.newProperty<int>("foresight_hi", cfg.foresight ? cfg.foresight->hi : 0);
    env.newProperty<unsigned int>("cultural_preferences", cfg.cultural_preferences ? 1u : 0u);  // eq. 5 (welfare.h)
    env.newProperty<unsigned int>("trade", cfg.trade ? 1u : 0u);                                 // rule T (trade.cuh)
    env.newProperty<unsigned int>("trade_down", cfg.trade_rounding == "down" ? 1u : 0u);
    env.newProperty<unsigned int>("credit", cfg.credit ? 1u : 0u);                                // rule L (credit.cuh)
    env.newProperty<int>("credit_duration", cfg.credit ? cfg.credit->first : 0);
    env.newProperty<double>("credit_rate", cfg.credit ? cfg.credit->second : 0.0);
    disease_properties(env, cfg);  // Chapter V (plan 2026-10-27-gpu-parity-part-d): newcomers' immune draws
    env.newProperty<unsigned int>("t", 0u);
    env.newProperty<unsigned int>("round", 1u);
    env.newProperty<unsigned int>("seasons_beta", cfg.seasons ? static_cast<unsigned int>(cfg.seasons->first) : 0u);
    env.newProperty<unsigned int>("seasons_gamma", cfg.seasons ? static_cast<unsigned int>(cfg.seasons->second) : 0u);
    env.newProperty<unsigned int>("winter_pulse", cfg.winter_growback == "pulse" ? 1u : 0u);
    // The turns (turns.cuh): the device store's and the newcomer slots' addresses, serial mode, the wave number.
    env.newProperty<uint64_t>("store", 0);
    env.newProperty<uint64_t>("newcomers", 0);
    env.newProperty<uint64_t>("dying", 0);  // rule I's table of the period's dying (store.h, DyingTable)
    env.newProperty<unsigned int>("serial_turns", cfg.serial() ? 1u : 0u);  // one turn per wave
    env.newProperty<unsigned int>("wave", 0u);
    landscape_macros(env, true);

    flamegpu::AgentDescription citizen = model.newAgent("citizen");
    for (const char* name : {"x", "y", "vision", "metabolism", "age", "max_age"}) citizen.newVariable<int>(name);
    citizen.newVariable<double>("sugar");  // holdings are double (spec 2026-10-25-gpu-full-parity, section 4)
    // Chapter III state (spec section 3). Without sex, fertility_start/end are NO_FERTILITY_START/END, Python's inf/-inf.
    citizen.newVariable<unsigned int>("uid");
    citizen.newVariable<unsigned int>("sex", SEX_NONE);
    citizen.newVariable<int>("fertility_start", NO_FERTILITY_START);
    citizen.newVariable<int>("fertility_end", NO_FERTILITY_END);
    citizen.newVariable<double>("initial_sugar");
    citizen.newVariable<uint64_t>("tags");  // bit i is tag i
    citizen.newVariable<unsigned int>("n_children");
    citizen.newVariable<unsigned int>("parent_a", NO_UID);
    citizen.newVariable<unsigned int>("parent_b", NO_UID);
    citizen.newVariable<unsigned int, MAX_FRIENDS>("friend_uid");
    citizen.newVariable<unsigned int, MAX_FRIENDS>("friend_dist");
    citizen.newVariable<unsigned int>("n_friends");
    citizen.newVariable<int>("disp_x");  // net displacement since birth, unwrapped across the torus edges
    citizen.newVariable<int>("disp_y");
    for (const char* name : {"moved", "neighbors", "settled", "priority", "target"}) citizen.newVariable<unsigned int>(name);
    citizen.newVariable<unsigned int>("look_seed");  // this period's looks, when look_stride > 1 (start_period)
    citizen.newVariable<unsigned int>("dir_order");  // this period's scan direction order, 2 bits each (start_period)
    citizen.newVariable<unsigned int>("row");        // the citizen's row in the store this period (publish)
    citizen.newVariable<uint64_t>("death_key");      // a newcomer's place among this period's deaths (store.h)
    citizen.newVariable<unsigned int>("nc_slot");    // a newcomer's slot while it takes its uid
    citizen.newVariable<unsigned int>("dying");      // reached its maximum age this period (rule I's layers)
    // Chapter IV state (plan 2026-10-26-gpu-parity-part-c): 0 without spice, as in Python.
    citizen.newVariable<double>("spice");
    citizen.newVariable<double>("initial_spice");
    citizen.newVariable<int>("spice_metabolism");
    citizen.newVariable<int>("foresight");  // phi (p.129), 0 when myopic
    // Chapter V state (plan 2026-10-27-gpu-parity-part-d): bit i is Python's element i; the diseases carried are
    // canonical ids in infection order, the array declared only with disease on so other runs carry none of it.
    citizen.newVariable<uint64_t>("immune_genotype");
    citizen.newVariable<uint64_t>("immune");
    citizen.newVariable<unsigned int>("n_diseases");
    if (cfg.disease()) citizen.newVariable<uint8_t, MAX_DISEASES>("diseases");
    flamegpu::AgentDescription cell = model.newAgent("cell");
    cell.newVariable<unsigned int>("capacity");  // the site's sugar capacity (make_cells)
    cell.newVariable<unsigned int>("spice_capacity");  // the sugar map mirrored east-west, 0 without spice (make_cells)

    flamegpu::ModelDescription movement("movement");
    describe_movement(movement, cfg);
    flamegpu::SubModelDescription movement_sub = model.newSubModel("movement", movement);
    movement_sub.bindAgent("citizen", "citizen", true, true);
    movement_sub.SubEnvironment(true);
    // FLAME GPU reseeds sub-models in name order (a std::map), so this name sorts after "movement" to leave the
    // movement sub-model's random stream as it was before diffusion passes existed.
    flamegpu::ModelDescription diffusion("pollution_diffusion");
    describe_diffusion(diffusion, cfg);
    flamegpu::SubModelDescription diffusion_sub = model.newSubModel("pollution_diffusion", diffusion);
    diffusion_sub.bindAgent("cell", "cell", true, true);
    diffusion_sub.SubEnvironment(true);

    flamegpu::AgentFunctionDescription occupy = citizen.newFunction("occupy_site", occupy_site);

    model.newLayer().addHostFunction(begin_period);
    flamegpu::LayerDescription initialise = model.newLayer();
    initialise.addAgentFunction(cell.newFunction("cell_initialise", cell_initialise));
    initialise.addAgentFunction(occupy);  // the founders' sites
    model.newLayer().addHostFunction(finish_init);
    model.newLayer().addAgentFunction(citizen.newFunction("start_period", start_period));
    if (!state().dump_order.empty()) model.newLayer().addHostFunction(record_order);  // --dump-order (tests)
    // With combat there is no movement M: each turn moves by combat_move (spec section 1).
    if (!cfg.combat()) model.newLayer().addSubModel(movement_sub);
    if (cfg.turns_on()) {
        // With an interaction rule, every turn after movement runs in the period's order (spec
        // 2026-10-25-gpu-full-parity, sections 1 and 2): publish, schedule, the turns, absorb, then old age.
        RunState& s = state();
        s.store = std::make_unique<StoreHost>(cfg, cfg.uid_capacity, s.check);
        env.setProperty<uint64_t>("store", s.store->device_address());
        if (cfg.credit) {  // rule L's loan book (loans.h), read and extended through the store
            const unsigned int cells = static_cast<unsigned int>(cfg.cells());
            s.loans = std::make_unique<LoanBook>(cells, 2 * cells, cfg.loan_capacity);
            s.store->attach_loans(s.loans->device());
        }
        flamegpu::ModelDescription turns("turns");  // sorts after "movement": its random stream stays as it was
        describe_turns(turns, cfg);
        flamegpu::SubModelDescription turns_sub = model.newSubModel("turns", turns);
        turns_sub.bindAgent("citizen", "citizen", true, true);
        turns_sub.SubEnvironment(true);
        model.newLayer().addHostFunction(prepare_turns);
        model.newLayer().addAgentFunction(cell.newFunction("stage_sites", stage_sites));
        model.newLayer().addAgentFunction(citizen.newFunction("publish", publish));
        model.newLayer().addHostFunction(schedule_turns);
        model.newLayer().addSubModel(turns_sub);
        model.newLayer().addAgentFunction(cell.newFunction("unstage_sites", unstage_sites));
        model.newLayer().addHostFunction(assign_births);
        if (cfg.trade) model.newLayer().addHostFunction(total_trades);  // rule T's statistics (turns.cuh)
        if (cfg.disease()) model.newLayer().addHostFunction(total_infections);  // rule E's (turns.cuh)
        if (cfg.credit) model.newLayer().addHostFunction(settle_turn_loans);  // rule L's book after the turns
        if (cfg.combat()) model.newLayer().addHostFunction(bury_newborns);  // combat's newborn victims (turns.cuh)
        flamegpu::AgentFunctionDescription absorb_fn = citizen.newFunction("absorb", absorb);
        absorb_fn.setAllowAgentDeath(true);
        if (cfg.replacement) absorb_fn.setAgentOutput(citizen);
        model.newLayer().addAgentFunction(absorb_fn);
        flamegpu::AgentFunctionDescription spawn_fn = cell.newFunction("spawn_newborns", spawn_newborns);
        spawn_fn.setAgentOutput(citizen);
        model.newLayer().addAgentFunction(spawn_fn);
        // Combat's newborn victims: counted, and with replacement each replaced by a cell (turns.cuh). Every later layer
        // leaves unplaced newcomers alone.
        if (cfg.combat()) {
            if (cfg.replacement) {
                flamegpu::AgentFunctionDescription replace_fn = cell.newFunction("replace_newborns", replace_newborns);
                replace_fn.setAgentOutput(citizen);
                model.newLayer().addAgentFunction(replace_fn);
            }
        }
        if (cfg.inheritance || cfg.credit) {
            // Old age through the table of the period's dying (turns.cuh): age and post the dying; with rule I count
            // and pay the heirs; then the dying die. With rule L the ledger follows: on_death for the dying, then
            // settle_loans, on each citizen's sugar (Python's order after aging).
            const bool pairs = cfg.inheritance && cfg.credit;  // a dying lender's heirs take its loans (loans.cu)
            s.dying = std::make_unique<DyingTable>(static_cast<unsigned int>(cfg.cells()), pairs);
            env.setProperty<uint64_t>("dying", s.dying->device_address());
            model.newLayer().addHostFunction(dying_posting);
            model.newLayer().addAgentFunction(citizen.newFunction("age_mark", age_mark));
            model.newLayer().addHostFunction(dying_sort);
            if (cfg.inheritance) {
                model.newLayer().addAgentFunction(citizen.newFunction("heirs_count", heirs_count));
                if (pairs) model.newLayer().addHostFunction(dying_pairs_sort);
                model.newLayer().addAgentFunction(citizen.newFunction("heirs_take", heirs_take));
            }
            flamegpu::AgentFunctionDescription die_fn = citizen.newFunction("die_old", die_old);
            die_fn.setAllowAgentDeath(true);
            if (cfg.replacement) die_fn.setAgentOutput(citizen);
            model.newLayer().addAgentFunction(die_fn);
            if (cfg.credit) {
                model.newLayer().addAgentFunction(citizen.newFunction("ledger_post", ledger_post));
                model.newLayer().addHostFunction(ledger);
                model.newLayer().addAgentFunction(citizen.newFunction("ledger_take", ledger_take));
            }
        } else {
            flamegpu::AgentFunctionDescription age_fn = citizen.newFunction("age_and_die", age_and_die);
            age_fn.setAllowAgentDeath(true);
            if (cfg.replacement) age_fn.setAgentOutput(citizen);
            model.newLayer().addAgentFunction(age_fn);
        }
    } else {
        flamegpu::AgentFunctionDescription metabolize = citizen.newFunction("metabolize_and_age", metabolize_and_age);
        metabolize.setAllowAgentDeath(true);
        // Replacement on the device (spec 2026-10-25): only when it is on, so other runs execute today's kernels.
        if (cfg.replacement) metabolize.setAgentOutput(citizen);
        model.newLayer().addAgentFunction(citizen.newFunction("commit_move", commit_move));
        model.newLayer().addAgentFunction(metabolize);
        // After metabolism, as Python counts each agent's neighbours after its own move and metabolism.
        model.newLayer().addAgentFunction(citizen.newFunction("count_neighbors", count_neighbors));
    }
    if (cfg.replacement) {
        // Newcomers' uids in the order of their deaths (store.h, NewcomerUids), then their sites.
        RunState& s = state();
        s.newcomers = std::make_unique<NewcomerUids>(static_cast<unsigned int>(cfg.cells()));
        env.setProperty<uint64_t>("newcomers", s.newcomers->device_address());
        model.newLayer().addAgentFunction(citizen.newFunction("newcomer_post", newcomer_post));
        model.newLayer().addHostFunction(assign_newcomers);
        model.newLayer().addAgentFunction(citizen.newFunction("newcomer_take", newcomer_take));
        model.newLayer().addAgentFunction(citizen.newFunction("place_newcomer", place_newcomer));
    }
    model.newLayer().addAgentFunction(cell.newFunction("cell_grow", cell_grow));
    model.newLayer().addAgentFunction(cell.newFunction("cell_commit", cell_commit));
    model.newLayer().addSubModel(diffusion_sub);
    model.addStepFunction(end_period);
}
