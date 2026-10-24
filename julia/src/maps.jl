# Resource capacity maps, read from the Python package's map folder (sugarscape/maps).

const MAPS_DIR = joinpath(dirname(dirname(@__DIR__)), "sugarscape", "maps")

"""
    parse_map(text) -> Matrix{Int}

A map file's text as capacities indexed `[x + 1, y + 1]` (x east, y north, y = 0 the southern row). The file holds
whitespace-separated integers, one line per row, the first line northernmost (docs/xl.md, "The map").
"""
function parse_map(text::AbstractString)
    rows = [parse.(Int, split(line)) for line in split(text, '\n') if !isempty(strip(line))]
    height, width = length(rows), length(rows[1])
    all(r -> length(r) == width, rows) ||
        throw(ArgumentError("map rows have different lengths"))
    cap = Matrix{Int}(undef, width, height)
    for (line, row) in enumerate(rows), x in 1:width
        cap[x, height - line + 1] = row[x]
    end
    return cap
end

load_map(name::AbstractString) = parse_map(read(joinpath(MAPS_DIR, name), String))

map_sha256(name::AbstractString) = bytes2hex(open(sha256, joinpath(MAPS_DIR, name)))
