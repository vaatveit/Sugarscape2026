# A live browser viewer for the Julia port's xxl VI-1 runs (docs/superpowers/specs/2026-11-10-xxl-viewer-design.md). Not
# part of the Sugarscape package: include this file, then `using .XxlViewer`.
module XxlViewer

using Sugarscape

export VIEWER_EXPS, DEFAULT_EXP, ViewerSettings, viewer_defaults, viewer_config, run_index, SERIES_KEYS, ViewerRun,
    advance!, series_since, total_debt,
    COLOUR_MODES, WEALTH_EDGES, DISEASE_STEPS, wealth_band, disease_step, tribe_code, culture_ones, ROLE_NONE, ROLE_LENDER,
    ROLE_BORROWER, ROLE_BOTH, credit_roles, cell_eighths, legend, ViewerFrame, capture_frame, encode_frame, lorenz_curve,
    VIEWER_KEEP

include("encoding.jl")
include("frame.jl")
include("run.jl")

end # module
