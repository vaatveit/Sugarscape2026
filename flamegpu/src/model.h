// The FLAME GPU model description: environment, macro properties, agents, layers and the movement sub-model.
#ifndef SRC_MODEL_H_
#define SRC_MODEL_H_

#include <climits>

#include "flamegpu/flamegpu.h"

#include "config.h"

// Size of every 1D landscape macro property; a site's index is x + y * width (design: Data layout).
constexpr unsigned int MAX_CELLS = SUGARSCAPE_MAX_CELLS;
// max_age of an agent that never dies of old age.
constexpr int IMMORTAL = INT_MAX;

// Chapter III (spec 2026-10-25-gpu-full-parity, section 3).
constexpr unsigned int SEX_NONE = 0u, SEX_F = 1u, SEX_M = 2u;
constexpr int NO_FERTILITY_START = INT_MAX;  // Python's fertility_start = inf: never fertile
constexpr int NO_FERTILITY_END = INT_MIN;    // Python's fertility_end = -inf
constexpr unsigned int NO_UID = 0xFFFFFFFFu;  // no parent: founders and newcomers
constexpr unsigned int MAX_FRIENDS = 5;       // networks of friends (p.79)

void describe_model(flamegpu::ModelDescription& model, const RunConfig& cfg);

#endif  // SRC_MODEL_H_
