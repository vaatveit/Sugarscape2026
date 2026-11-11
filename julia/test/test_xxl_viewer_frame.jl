# The xxl viewer's frames (julia/viewer/encoding.jl, frame.jl): the codes, the legend, what a run captures each period,
# and the binary layout the page decodes.
isdefined(@__MODULE__, :XxlViewer) || include(joinpath(@__DIR__, "..", "viewer", "XxlViewer.jl"))
using Sugarscape, Test
using .XxlViewer

const VF_ID = "VI-1-assim-k4"
vf_settings() = viewer_defaults(VF_ID)

# The test's own decoder of a frame's bytes: a named tuple of the values in the layout's order.
function vf_decode(bytes::Vector{UInt8})
    @assert String(bytes[1:4]) == "SXV1"
    at(T, off, n) = (collect(reinterpret(T, bytes[(off + 1):(off + n * sizeof(T))])), off + n * sizeof(T))
    t = Int(only(reinterpret(Int32, bytes[5:8])))
    width, height = Int.(reinterpret(UInt16, bytes[9:12]))
    n, nk, nc = Int.(reinterpret(UInt32, bytes[13:24]))
    ntags = Int(bytes[25])
    @assert all(==(0x00), bytes[26:32])
    off = 32
    sugar, off = at(Float64, off, n)
    spice, off = at(Float64, off, n)
    lorenz, off = at(Float64, off, 101)
    gini, off = at(Float64, off, 1)
    id, off = at(UInt32, off, n)
    u16 = Dict{Symbol,Vector{UInt16}}()
    for (name, count) in (:x => n, :y => n, :tags => n, :age => n, :lender => n, :borrower => n, :kill_x => nk,
        :kill_y => nk, :change_x => nc, :change_y => nc)
        u16[name], off = at(UInt16, off, count)
    end
    u8 = Dict{Symbol,Vector{UInt8}}()
    for (name, count) in (:tribe => n, :culture => n, :band => n, :disease_step => n, :role => n, :diseases => n,
        :cell_sugar => width * height, :cell_spice => width * height)
        u8[name], off = at(UInt8, off, count)
    end
    @assert off == length(bytes)
    return (; t, width, height, ntags, sugar, spice, lorenz, gini=only(gini), id, u16, u8)
end

@testset "frame codes" begin
    @test wealth_band.([0, 0.99, 1, 2.99, 3, 2999.9, 3000, 1e9]) == UInt8[0, 0, 1, 1, 2, 7, 8, 8]
    @test disease_step.([0, 1, 2, 3, 4, 5, 7, 8, 30]) == UInt8[0, 1, 2, 3, 3, 4, 4, 5, 5]
    @test cell_eighths(2.125) == 17
    @test cell_eighths(0.0) == 0
    @test_throws ErrorException cell_eighths(0.1)
    @test_throws ErrorException cell_eighths(40.0)
    @test_throws ErrorException cell_eighths(-0.125)
    @test COLOUR_MODES == ["tribe", "culture", "wealth", "disease", "credit"]
    @test (ROLE_NONE, ROLE_LENDER, ROLE_BORROWER, ROLE_BOTH) == (0, 1, 2, 3)
end

@testset "frame legend" begin
    lg = legend(viewer_config(vf_settings()))
    @test lg["modes"] == COLOUR_MODES
    for (mode, size) in zip(COLOUR_MODES, (2, 12, 9, 6, 4))
        @test length(lg["palettes"][mode]) == size
        @test length(unique(lg["palettes"][mode])) == size
        @test length(lg["labels"][mode]) == size
        @test all(c -> occursin(r"^#[0-9a-f]{6}$", c), lg["palettes"][mode])
    end
    @test lg["palettes"]["tribe"] == ["#2563eb", "#c0392b"]
    @test lg["kill_colour"] == "#000000"
    @test lg["change_colour"] == "#d4a000"
    @test lg["mark_periods"] == 10
    @test lg["max_level"] == 4
    @test lg["ntags"] == 11
    @test lg["wealth_edges"] == collect(WEALTH_EDGES)
    @test lg["disease_steps"] == collect(DISEASE_STEPS)
end

@testset "frame counts" begin
    s = vf_settings()
    r = ViewerRun(ViewerSettings(VF_ID, s.seed + 1, s.h, s.k))
    for _ in 1:12
        @test advance!(r)
    end
    f0 = vf_decode(r.frames[0])
    @test f0.t == 0
    @test length(f0.u16[:kill_x]) == 0
    @test length(f0.u16[:change_x]) == 0
    for t in 0:12
        f = vf_decode(r.frames[t])
        @test f.t == t
        @test length(f.id) == r.series["population"][t + 1]
        row = r.metric_rows[t + 1]
        @test count(in((1, 3)), f.u8[:role]) == row[r.metric_index["n_lenders"]]
        @test count(in((2, 3)), f.u8[:role]) == row[r.metric_index["n_borrowers"]]
        @test count(==(3), f.u8[:role]) == row[r.metric_index["n_both"]]
        @test f.gini ≈ r.series["gini"][t + 1] rtol = 1e-12
        @test f.lorenz[1] == 0
        @test f.lorenz[101] ≈ 1
        @test issorted(f.lorenz)
        @test count(==(0x00), f.u8[:tribe]) == r.series["n_blue"][t + 1]
        if t >= 1
            @test length(f.u16[:kill_x]) == r.series["killed_blue"][t + 1] + r.series["killed_red"][t + 1]
            @test length(f.u16[:change_x]) == r.series["tribe_changes"][t + 1]
        end
    end
    @test sum(length(vf_decode(r.frames[t]).u16[:kill_x]) for t in 1:12) > 0
    @test sum(length(vf_decode(r.frames[t]).u16[:change_x]) for t in 1:12) > 0

    @testset "columns and cells match the model" begin
        m = r.model
        d = vf_decode(r.frames[m.t])
        @test length(d.id) == length(m.agents)
        for (i, a) in enumerate(m.agents)
            @test d.id[i] == a.id
            @test (d.u16[:x][i], d.u16[:y][i]) == (a.x, a.y)
            @test d.u16[:tags][i] == a.tags
            @test d.u16[:age][i] == a.age
            @test d.sugar[i] == a.sugar
            @test d.spice[i] == a.spice
            @test d.u8[:tribe][i] == (Sugarscape.tribe(a) === :red ? 1 : 0)
            @test d.u8[:culture][i] == count_ones(a.tags)
            @test d.u8[:band][i] == wealth_band(a.sugar + a.spice)
            @test d.u8[:disease_step][i] == disease_step(length(a.diseases))
            @test d.u8[:diseases][i] == length(a.diseases)
            nl = count(l -> l.lender === a, m.loans)
            nb = count(l -> l.borrower === a, m.loans)
            @test d.u16[:lender][i] == nl
            @test d.u16[:borrower][i] == nb
            @test d.u8[:role][i] == (nl > 0 ? 1 : 0) + (nb > 0 ? 2 : 0)
        end
        w, h = d.width, d.height
        @test (w, h) == (m.config.width, m.config.height)
        for (x, y) in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (div(w, 2), div(h, 3)), (7, 11))
            @test d.u8[:cell_sugar][y * w + x + 1] == cell_eighths(m.landscape.sugar[x + 1, y + 1])
            @test d.u8[:cell_spice][y * w + x + 1] == cell_eighths(m.landscape.spice[x + 1, y + 1])
        end
        # an asymmetric landscape cell must catch a transpose: the sugar map is not symmetric
        @test any(d.u8[:cell_sugar][y * w + x + 1] != d.u8[:cell_sugar][x * w + y + 1] for x in 0:min(w, h) - 1, y in 0:min(w, h) - 1)
    end
end

# A frame by hand: 3 by 2 cells, 2 agents, 1 kill, 1 change.
function vf_hand_frame()
    return ViewerFrame(
        7, 3, 2, 11,
        [1.5, 20.0], [0.25, 0.0], [[0.0, 0.0]; fill(0.5, 98); [1.0]], 0.375,
        UInt32[5, 70000],
        UInt16[0, 2], UInt16[1, 0], UInt16[0x0a5, 0x7ff], UInt16[3, 99], UInt16[1, 0], UInt16[0, 2],
        UInt16[1], UInt16[1], UInt16[2], UInt16[0],
        UInt8[0, 1], UInt8[5, 8], UInt8[1, 2], UInt8[0, 3], UInt8[3, 0], UInt8[0, 4],
        UInt8[0, 8, 16, 17, 32, 255], UInt8[1, 2, 3, 4, 5, 6],
    )
end

function vf_hand_json()
    f = vf_hand_frame()
    vec(v) = "[" * join(v, ", ") * "]"
    return """{
  "t": $(f.t), "width": $(f.width), "height": $(f.height), "ntags": $(f.ntags),
  "sugar": $(vec(f.sugar)), "spice": $(vec(f.spice)),
  "lorenz": $(vec(f.lorenz)), "gini": $(f.gini),
  "id": $(vec(f.id)),
  "x": $(vec(f.x)), "y": $(vec(f.y)), "tags": $(vec(f.tags)), "age": $(vec(f.age)),
  "lender": $(vec(f.lender)), "borrower": $(vec(f.borrower)),
  "kill_x": $(vec(f.kill_x)), "kill_y": $(vec(f.kill_y)),
  "change_x": $(vec(f.change_x)), "change_y": $(vec(f.change_y)),
  "tribe": $(vec(f.tribe)), "culture": $(vec(f.culture)), "band": $(vec(f.band)),
  "disease_step": $(vec(f.disease_step)), "role": $(vec(f.role)), "diseases": $(vec(f.diseases)),
  "cell_sugar": $(vec(f.cell_sugar)), "cell_spice": $(vec(f.cell_spice))
}
"""
end

@testset "frame layout" begin
    f = vf_hand_frame()
    bytes = encode_frame(f)
    n, nk, nc, cells = 2, 1, 1, 6
    @test length(bytes) == 32 + 8 * (2n + 101 + 1) + 4n + 2 * (6n + 2nk + 2nc) + 6n + 2cells
    @test bytes[1:4] == b"SXV1"
    d = vf_decode(bytes)
    @test (d.t, d.width, d.height, d.ntags) == (7, 3, 2, 11)
    @test d.sugar == f.sugar && d.spice == f.spice && d.lorenz == f.lorenz && d.gini == f.gini
    @test d.id == f.id
    for name in (:x, :y, :tags, :age, :lender, :borrower, :kill_x, :kill_y, :change_x, :change_y)
        @test d.u16[name] == getfield(f, name)
    end
    for name in (:tribe, :culture, :band, :disease_step, :role, :diseases, :cell_sugar, :cell_spice)
        @test d.u8[name] == getfield(f, name)
    end

    dir = joinpath(@__DIR__, "js")
    mkpath(dir)
    for (name, content) in (("fixture-frame.bin", bytes), ("fixture-frame.json", Vector{UInt8}(vf_hand_json())))
        path = joinpath(dir, name)
        isfile(path) || write(path, content)
        @test read(path) == content
    end
end

@testset "empty frame" begin
    f = ViewerFrame(3, 2, 2, 11, Float64[], Float64[], fill(NaN, 101), NaN, UInt32[], UInt16[], UInt16[], UInt16[], UInt16[],
        UInt16[], UInt16[], UInt16[], UInt16[], UInt16[], UInt16[], UInt8[], UInt8[], UInt8[], UInt8[], UInt8[], UInt8[],
        UInt8[0, 0, 0, 0], UInt8[0, 0, 0, 0])
    d = vf_decode(encode_frame(f))
    @test isempty(d.id)
    @test all(isnan, d.lorenz)
    @test isnan(d.gini)
    @test lorenz_curve(Float64[]) |> v -> length(v) == 101 && all(isnan, v)
    @test isnan(Sugarscape.gini(Float64[]))
end

@testset "frame keep" begin
    s = vf_settings()
    r = ViewerRun(ViewerSettings(VF_ID, s.seed, s.h, s.k); keep=5)
    for _ in 1:8
        advance!(r)
    end
    @test sort(collect(keys(r.frames))) == collect(4:8)
    @test ViewerRun(ViewerSettings(VF_ID, s.seed, s.h, s.k)).keep == VIEWER_KEEP
end
