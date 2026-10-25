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
}

// The movement sub-model: scan and resolve until every citizen has settled (design: One period, step 2).
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
    citizen.newVariable<int>("x");
    citizen.newVariable<int>("y");
    citizen.newVariable<int>("vision");
    citizen.newVariable<float>("sugar");
    citizen.newVariable<unsigned int>("moved");
    citizen.newVariable<unsigned int>("settled");
    citizen.newVariable<unsigned int>("priority");
    citizen.newVariable<unsigned int>("target");
    sub.newLayer().addAgentFunction(citizen.newFunction("scan", scan));
    sub.newLayer().addAgentFunction(citizen.newFunction("resolve", resolve));
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
    env.newProperty<unsigned int>("t", 0u);
    env.newProperty<unsigned int>("round", 1u);
    env.newProperty<unsigned int>("seasons_beta", cfg.seasons ? static_cast<unsigned int>(cfg.seasons->first) : 0u);
    env.newProperty<unsigned int>("seasons_gamma", cfg.seasons ? static_cast<unsigned int>(cfg.seasons->second) : 0u);
    env.newProperty<unsigned int>("winter_pulse", cfg.winter_growback == "pulse" ? 1u : 0u);
    landscape_macros(env, true);

    flamegpu::AgentDescription citizen = model.newAgent("citizen");
    for (const char* name : {"x", "y", "vision", "metabolism", "age", "max_age"}) citizen.newVariable<int>(name);
    citizen.newVariable<float>("sugar");
    for (const char* name : {"moved", "neighbors", "settled", "priority", "target"}) citizen.newVariable<unsigned int>(name);
    citizen.newVariable<unsigned int>("look_seed");  // this period's looks, when look_stride > 1 (start_period)
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

    flamegpu::AgentFunctionDescription occupy = citizen.newFunction("occupy_site", occupy_site);

    model.newLayer().addHostFunction(begin_period);
    flamegpu::LayerDescription initialise = model.newLayer();
    initialise.addAgentFunction(cell.newFunction("cell_initialise", cell_initialise));
    initialise.addAgentFunction(occupy);  // the founders' sites
    model.newLayer().addHostFunction(finish_init);
    model.newLayer().addAgentFunction(citizen.newFunction("start_period", start_period));
    model.newLayer().addSubModel(movement_sub);
    model.newLayer().addAgentFunction(citizen.newFunction("count_neighbors", count_neighbors));
    model.newLayer().addAgentFunction(metabolize);
    model.newLayer().addHostFunction(replace_dead);
    model.newLayer().addAgentFunction(occupy);  // the newcomers' sites
    model.newLayer().addAgentFunction(cell.newFunction("cell_grow", cell_grow));
    model.newLayer().addAgentFunction(cell.newFunction("cell_commit", cell_commit));
    model.newLayer().addSubModel(diffusion_sub);
    model.addStepFunction(end_period);
}
