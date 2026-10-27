// The welfare function and the marginal rate of substitution, line for line with Python's sugarscape.rules.welfare
// (Chapter IV, eqs. 1, 3 and 5, pp.97-104 and 124). Host and device: movement scores sites with welfare (Task 3 of
// plan 2026-10-26-gpu-parity-part-c), and trade bargains with both (Task 5).
#ifndef SRC_WELFARE_H_
#define SRC_WELFARE_H_

#include <cfloat>
#include <cmath>
#include <cstdint>

#ifdef __CUDACC__
#define WELFARE_FN __host__ __device__ inline
#else
#define WELFARE_FN inline
#endif

// f in eq. 5: the share of the agent's tags that are 0 when preferences are cultural (p.124); 0.5 otherwise, which
// reduces eq. 5 to eq. 1. Without tags (tag_length 0) it is 0.5 too, as Python's tags of None.
WELFARE_FN double preference_fraction(uint64_t tags, int tag_length, bool cultural) {
    if (!cultural || tag_length == 0) return 0.5;
    int ones = 0;
    for (int i = 0; i < tag_length; ++i) ones += static_cast<int>((tags >> i) & 1u);
    return static_cast<double>(tag_length - ones) / static_cast<double>(tag_length);
}

// W(w1, w2) = w1^(a1 / mu) * w2^(a2 / mu), a1 = sugar_burn * f, a2 = spice_metabolism * (1 - f), mu = a1 + a2. Holdings
// below 0 count as 0; a zero exponent makes its factor 1 (so mu = 0 divides nothing).
WELFARE_FN double welfare(double sugar_burn, int spice_metabolism, double f, double w1, double w2) {
    const double a1 = sugar_burn * f, a2 = static_cast<double>(spice_metabolism) * (1.0 - f);
    const double mu = a1 + a2;
    w1 = w1 > 0.0 ? w1 : 0.0;
    w2 = w2 > 0.0 ? w2 : 0.0;
    const double left = a1 != 0.0 ? pow(w1, a1 / mu) : 1.0;
    const double right = a2 != 0.0 ? pow(w2, a2 / mu) : 1.0;
    return left * right;
}

// Infinity and finiteness by comparison: MSVC's std::isinf and std::isfinite are host-only templates, which device code
// must not call.
WELFARE_FN bool is_infinite(double v) { return v > DBL_MAX || v < -DBL_MAX; }
WELFARE_FN bool is_finite(double v) { return v == v && !is_infinite(v); }

// Spice the agent would give for one sugar: (w2 / a2) / (w1 / a1) (eq. 3, eq. 5's form); inf or 0 when a holding or a
// weight is zero, nan when both sides are.
WELFARE_FN double mrs(double sugar_burn, int spice_metabolism, double f, double w1, double w2) {
    const double a1 = sugar_burn * f, a2 = static_cast<double>(spice_metabolism) * (1.0 - f);
    w1 = w1 > 0.0 ? w1 : 0.0;
    w2 = w2 > 0.0 ? w2 : 0.0;
    const double numerator = a2 == 0.0 ? INFINITY : w2 / a2;
    const double denominator = a1 == 0.0 ? INFINITY : w1 / a1;
    if (denominator == 0.0) return numerator > 0.0 ? INFINITY : NAN;
    if (is_infinite(denominator)) return is_finite(numerator) ? 0.0 : NAN;
    return numerator / denominator;
}

#undef WELFARE_FN

#endif  // SRC_WELFARE_H_
