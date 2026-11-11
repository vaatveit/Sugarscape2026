# The xxl viewer: a live browser view of one xxl VI-1 run (an experiment of the combat study, in today's world) at
# http://127.0.0.1:<port>/. It needs two threads, one for the server and one for the stepper:
#   julia --project=julia --threads=2,1 julia/xxl_viewer.jl [--port 8766]
# Ctrl+C stops it.
include(joinpath(@__DIR__, "viewer", "XxlViewer.jl"))
using .XxlViewer

function viewer_main(args)
    port = 8766
    i = 1
    while i <= length(args)
        if args[i] in ("-h", "--help")
            println("usage: julia --project=julia --threads=2,1 julia/xxl_viewer.jl [--port 8766]")
            return 0
        elseif args[i] == "--port" && i < length(args)
            port = tryparse(Int, args[i+1])
            (port !== nothing && 0 <= port <= 65535) || (println(stderr, "xxl viewer: --port needs a number from 0 to 65535"); return 2)
            i += 2
        else
            println(stderr, "xxl viewer: unknown or incomplete option ", args[i], " (see --help)")
            return 2
        end
    end
    if !(Threads.nthreads(:default) >= 1 && Threads.nthreads(:interactive) >= 1 && Threads.nthreads() >= 2)
        println(stderr, "xxl viewer: needs one default and one interactive thread; run with --threads=2,1")
        return 1
    end
    s = start_viewer(; port=port)
    println("xxl viewer at http://127.0.0.1:", port == 0 ? XxlViewer.HTTP.port(s.server) : port, "/ (Ctrl+C to stop)")
    flush(stdout)
    try
        wait(s.server)
    catch e
        e isa InterruptException || rethrow()
    finally
        stop_viewer(s)
    end
    return 0
end

exit(viewer_main(ARGS))
