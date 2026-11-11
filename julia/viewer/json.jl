# The viewer's JSON writer (HTTP.jl has none): just the values the routes send. A value the model leaves undefined (NaN,
# ±Inf) is written as null, never as a number.

"""
    to_json(x) -> String

`x` as JSON text: a `Dict` as an object (keys as strings, sorted), a `NamedTuple` as an object in its own key order, a
vector or tuple as an array, a number (NaN and ±Inf as `null`, a whole number without `.0`), a string (escaped), a
`Bool`, or `nothing` as `null`.
"""
to_json(x) = sprint(write_json, x)

write_json(io::IO, ::Nothing) = print(io, "null")
write_json(io::IO, x::Bool) = print(io, x ? "true" : "false")
write_json(io::IO, x::Integer) = print(io, x)

function write_json(io::IO, x::Real)
    f = Float64(x)
    if !isfinite(f)
        print(io, "null")
    elseif isinteger(f) && abs(f) < 2.0^53
        print(io, Int64(f))
    else
        print(io, repr(f))  # shortest round-trip form, e.g. 2.5 or 1.0e20: valid JSON numbers
    end
    return nothing
end

write_json(io::IO, x::Symbol) = write_json(io, String(x))

function write_json(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif c < ' '
            print(io, "\\u", string(UInt32(c); base=16, pad=4))
        else
            print(io, c)
        end
    end
    print(io, '"')
    return nothing
end

function write_json(io::IO, v::Union{AbstractVector,Tuple})
    print(io, '[')
    for (i, x) in enumerate(v)
        i > 1 && print(io, ',')
        write_json(io, x)
    end
    print(io, ']')
    return nothing
end

function write_members(io::IO, pairs)
    print(io, '{')
    for (i, (k, v)) in enumerate(pairs)
        i > 1 && print(io, ',')
        write_json(io, string(k))
        print(io, ':')
        write_json(io, v)
    end
    print(io, '}')
    return nothing
end

write_json(io::IO, d::AbstractDict) = write_members(io, sort!([string(k) => v for (k, v) in d]; by=first))
write_json(io::IO, nt::NamedTuple) = write_members(io, pairs(nt))
