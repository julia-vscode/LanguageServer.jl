module LanguageServer

using Compat
using JSON
using Lint
using URIParser

include("jsonrpc.jl")
include("protocol.jl")
include("languageserver.jl")
include("parse.jl")
include("provider_diagnostics.jl")
include("provider_misc.jl")
include("provider_hover.jl")
include("provider_completions.jl")
include("provider_definitions.jl")
include("provider_signatures.jl")
include("transport.jl")
include("provider_symbols.jl")
include("utilities.jl")

type Document
    data::Vector{UInt8}
    blocks::Vector{Any}
end

type LanguageServerInstance
    pipe_in
    pipe_out

    rootPath::String 
    documents::Dict{String,Document}
    DocStore::Dict{String,Any}

    debug_mode::Bool

    function LanguageServerInstance(pipe_in,pipe_out, debug_mode::Bool)
        new(pipe_in,pipe_out,"",Dict{String,Document}(),Dict{String,Any}(), debug_mode)
    end
end

function send(message, server)
    message_json = JSON.json(message)

    write_transport_layer(server.pipe_out,message_json, server)
end

function Base.run(server::LanguageServerInstance)
    while true
        message = read_transport_layer(server.pipe_in, server)
        request = parse(Request, message)

        process(request, server)
    end
end

end
