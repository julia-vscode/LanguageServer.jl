haskeynotnull(d::Dict, k) = haskey(d, k) && d[k] != nothing

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
    actions::Nullable{Vector{MessageActionItem}}
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
