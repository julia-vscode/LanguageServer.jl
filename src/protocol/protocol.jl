haskeynotnull(d::Dict, k) = haskey(d, k) && d[k] != nothing

macro json_read(arg)
    ex = quote
        $((arg))

        function $((arg.args[2]))(d::Dict)
        end
    end
    fex = :($((arg.args[2]))())
    for a in arg.args[3].args
        if !(a isa LineNumberNode)
            fn = string(a.args[1])            
            if a.args[2] isa Expr && length(a.args[2].args) > 1 && a.args[2].head == :curly && a.args[2].args[1] == :Union
                isnullable = true
                t = a.args[2].args[3]
            else
                isnullable = false
                t = a.args[2]
            end
            if t isa Expr && t.head == :curly && t.args[2] != :Any
                f = :($(t.args[2]).(d[$fn]))
            elseif t != :Any
                f = :($(t)(d[$fn]))
            else
                f = :(d[$fn])
            end
            if isnullable
                f = :(haskeynotnull(d,$fn) ? $f : nothing)
            end
            push!(fex.args, f)
        end
    end
    push!(ex.args[end].args[2].args, fex)
    return esc(ex)
end

include("basic.jl")
include("configuration.jl")
include("document.jl")
include("providers.jl")

const MessageType = Dict("Error" => 1, "Warning" => 2, "Info" => 3, "Log" => 4)

function Message(t::Int, text::AbstractString)
    Dict("jsonrpc" => "2.0", "method" => "window/showMessage", "params" => Dict("type" => t, "message" => text))
end

mutable struct ShowMessageParams
    typ::Integer
    message::String
end

JSON.lower(a::ShowMessageParams) = Dict("type" => a.typ, "message" => a.message)


mutable struct MessageActionItem
    title::String
end

mutable struct ShowMessageRequestParams
    typ::Integer
    message::String
    actions::Union{Nothing,Vector{MessageActionItem}}
end

function JSON.lower(a::ShowMessageRequestParams)
    d = Dict("type" => a.typ, "message" => a.message)
    if isnull(a.actions)
        d["actions"] = JSON.lower(a.actions)
    end
    return d
end

mutable struct LogMessageParams
    typ::Integer
    message::String
end

JSON.lower(a::LogMessageParams) = Dict("type" => a.typ, "message" => a.message)


mutable struct CancelParams
    id::Union{String,Int64}
end
CancelParams(d::Dict) = CancelParams(d["id"])
