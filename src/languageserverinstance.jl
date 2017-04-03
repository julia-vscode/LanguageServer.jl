type LanguageServerInstance
    pipe_in
    pipe_out

    rootPath::String 
    documents::Dict{String,Document}
    cache::Dict{Any,Any}

    debug_mode::Bool
    runlinter::Bool

    user_pkg_dir::String

    function LanguageServerInstance(pipe_in,pipe_out, debug_mode::Bool, user_pkg_dir::AbstractString=haskey(ENV, "JULIA_PKGDIR") ? ENV["JULIA_PKGDIR"] : joinpath(homedir(),".julia"))
        cache = Dict()

        new(pipe_in,pipe_out,"", Dict{String,Document}(), cache, debug_mode, false, user_pkg_dir)
    end
end

function send(message, server)
    message_json = JSON.json(message)

    write_transport_layer(server.pipe_out,message_json, server.debug_mode)
end

function Base.run(server::LanguageServerInstance)
    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        request = parse(JSONRPC.Request, message)

        process(request, server)
    end
end
