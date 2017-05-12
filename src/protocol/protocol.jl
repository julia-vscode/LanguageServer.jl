haskeynotnull(d::Dict, k) = haskey(d, k) && d[k] != nothing

include("basic.jl")
include("configuration.jl")
include("document.jl")
include("providers.jl")

const MessageType = Dict("Error" => 1, "Warning" => 2, "Info" => 3, "Log" => 4)

function Message(t::Int, text::AbstractString)
    Dict("jsonrpc"=>"2.0", "method"=>"window/showMessage", "params"=>Dict("type"=>t, "message"=>text))
end

type ShowMessageParams
    typ::Integer
    message::String
end

JSON.lower(a::ShowMessageParams) = Dict("type" => a.typ, "message" => a.message)


type MessageActionItem
    title::String
end

type ShowMessageRequestParams
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

type LogMessageParams
    typ::Integer
    message::String
end

JSON.lower(a::LogMessageParams) = Dict("type" => a.typ, "message" => a.message)


type CancelParams
    id::Union{String,Int64}
end
CancelParams(d::Dict) = CancelParams(d["id"])