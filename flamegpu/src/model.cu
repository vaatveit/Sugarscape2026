#include "model.h"

#include "host_state.h"
#include "movement.cuh"
#include "rules.cuh"

namespace {

void landscape_macros(flamegpu::EnvironmentDescription env, bool all) {
    env.newMacroProperty<unsigned int, MAX_CELLS>("occupied");
    env.newMacroProperty<float, MAX_CELLS>("sugar");
    env.newMacroProperty<float, MAX_CELLS>("pollution");
    env.newMacroProperty<uint64_t, MAX_CELLS>("claim");
    if (!all) return;
    env.newMacroProperty<float, MAX_CELLS>("sugar_next");
    env.newMacroProperty<float, MAX_CELLS>("pollution_next");
    env.newMacroProperty<unsigned int>("deaths");
    env.newMacroProperty<unsigned int>("next_uid");  // the next uid in Python's creation order (spec section 3)
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
    landscape_macros(env, false);
    flamegpu::AgentDescription citizen = sub.newAgent("citizen");
    citizen.newVariable<unsigned int>("look_seed");
    citizen.newVariable<unsigned int>("dir_order");
    citizen.newVariable<int>("x");
    citizen.newVariable<int>("y");
    citizen.newVariable<int>("vision");
    citizen.newVariable<double>("sugar");
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
    env.newProperty<unsigned int>("t", 0u);
    env.newProperty<unsigned int>("round", 1u);
    env.newProperty<unsigned int>("seasons_beta", cfg.seasons ? static_cast<unsigned int>(cfg.seasons->first) : 0u);
    env.newProperty<unsigned int>("seasons_gamma", cfg.seasons ? static_cast<unsigned int>(cfg.seasons->second) : 0u);
    env.newProperty<unsigned int>("winter_pulse", cfg.winter_growback == "pulse" ? 1u : 0u);
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
    flamegpu::AgentDescription cell = model.newAgent("cell");
    cell.newVariable<unsigned int>("capacity");  // the site's sugar capacity (make_cells)

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

    flamegpu::AgentFunctionDescription metabolize = citizen.newFunction("metabolize_and_age", metabolize_and_age);
    metabolize.setAllowAgentDeath(true);
    // Replacement on the device (spec 2026-10-25): only when it is on, so other runs execute today's kernels.
    if (cfg.replacement) metabolize.setAgentOutput(citizen);

    flamegpu::AgentFunctionDescription occupy = citizen.newFunction("occupy_site", occupy_site);

    model.newLayer().addHostFunction(begin_period);
    flamegpu::LayerDescription initialise = model.newLayer();
    initialise.addAgentFunction(cell.newFunction("cell_initialise", cell_initialise));
    initialise.addAgentFunction(occupy);  // the founders' sites
    model.newLayer().addHostFunction(finish_init);
    model.newLayer().addAgentFunction(citizen.newFunction("start_period", start_period));
    model.newLayer().addSubModel(movement_sub);
    model.newLayer().addAgentFunction(citizen.newFunction("commit_move", commit_move));
    model.newLayer().addAgentFunction(metabolize);
    // After metabolism, as Python counts each agent's neighbours after its own move and metabolism.
    model.newLayer().addAgentFunction(citizen.newFunction("count_neighbors", count_neighbors));
    if (cfg.replacement) model.newLayer().addAgentFunction(citizen.newFunction("place_newcomer", place_newcomer));
    model.newLayer().addAgentFunction(cell.newFunction("cell_grow", cell_grow));
    model.newLayer().addAgentFunction(cell.newFunction("cell_commit", cell_commit));
    model.newLayer().addSubModel(diffusion_sub);
    model.addStepFunction(end_period);
}
