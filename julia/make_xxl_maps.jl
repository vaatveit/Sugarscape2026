# Writes the two generated xxl maps (xxl rule 6) into sugarscape/maps/ and prints the seeds and SHA-256s:
#   julia --project=julia julia/make_xxl_maps.jl
# Each map has the xl map's number of sites of every capacity 0-4. The search for a seed whose rank cuts all have gaps
# of at least 1e-9 starts at 1 for sugar and 1001 for spice; copy the seeds printed into XXL_TERRAIN_SEEDS
# (julia/src/xxl/terrain.jl) if they differ.
using Sugarscape
using Sugarscape: map_text, XXL_SPICE_MAP

counts = Tuple(count(==(c), load_map("sugar-map-xl.txt")) for c in 0:4)
for (name, first_seed) in (("sugar-map-xxl.txt", 1), (XXL_SPICE_MAP, 1001))
    cap, seed = generate_map(first_seed, counts)
    write(joinpath(MAPS_DIR, name), map_text(cap))
    @assert load_map(name) == cap
    println(name, ": seed ", seed, ", sha256 ", map_sha256(name))
end
