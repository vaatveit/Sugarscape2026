# The xxl viewer page's JavaScript tests (julia/test/js/*.test.mjs), run with `node --test` from the repository root.
# Skipped with a note when node is not installed; a failure prints node's output.
using Test

@testset "xxl viewer page (node --test)" begin
    node = Sys.which("node")
    if node === nothing
        @info "node is not installed: skipping the xxl viewer page's JavaScript tests (julia/test/js)"
        @test_skip "node --test julia/test/js"
    else
        root = normpath(joinpath(@__DIR__, "..", ".."))
        files = sort(filter(f -> endswith(f, ".test.mjs"), readdir(joinpath(@__DIR__, "js"))))
        @test !isempty(files)
        # Paths relative to the root with forward slashes, which node reads on every platform.
        cmd = Cmd(`$node --test $(["julia/test/js/" * f for f in files])`; dir=root)
        out = IOBuffer()
        proc = run(pipeline(ignorestatus(cmd); stdout=out, stderr=out))
        passed = proc.exitcode == 0
        passed || println(String(take!(out)))
        @test passed
    end
end
