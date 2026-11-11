# A live browser viewer for the Julia port's xxl VI-1 runs (docs/superpowers/specs/2026-11-10-xxl-viewer-design.md). Not
# part of the Sugarscape package: include this file, then `using .XxlViewer`.
module XxlViewer

using Sugarscape

export VIEWER_EXPS, DEFAULT_EXP, ViewerSettings, viewer_defaults, viewer_config, run_index, SERIES_KEYS, ViewerRun,
    advance!, series_since, total_debt

include("run.jl")

end # module
