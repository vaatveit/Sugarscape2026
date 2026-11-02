# Reads finished runs of candidate disease lists against the baseline, for the disease-list study (screening): for each arm
# the reading table (X9, X10 as a mean and per seed, the trough, extinction) with pass, near or fail and the arm it chooses;
# the readings of every run with the baseline's first, and the arms' ratios to it with intervals that resample each side
# on its own; and, for a run that goes past t = 500, the readings at t = 501-1,000 and t = 1,501-2,000 that it reaches, its
# diseases at its last period, its end share sick, the seeds losing a disease and the share sick by diseases. --base and
# the folders of --arms are run folders of --out (the extinction test's, results-julia-xxl/ by default); an arm is
# NAME=FOLDER. It reads only finished seeds and runs nothing, so it can be used while a run is going. The report goes to
# <out>/disease-list-<label>.md.
#   julia --project=julia julia/xxl_disease_list.jl --base FOLDER --arms NAME=FOLDER,NAME=FOLDER,… [--out DIR]
#         [--label NAME]
using Sugarscape

exit(Sugarscape.disease_list_main(ARGS))
