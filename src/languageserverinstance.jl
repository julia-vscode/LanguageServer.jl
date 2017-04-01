type LanguageServerInstance
    pipe_in
    pipe_out

    rootPath::String 
    documents::Dict{String,Document}
    cache::Dict{Any,Any}
    user_modules::Channel{Symbol}
    user_pkgdir::String

    debug_mode::Bool
    runlinter::Bool

    function LanguageServerInstance(pipe_in,pipe_out, debug_mode::Bool, user_pkgdir::AbstractString=ENV["JULIA_PKGDIR"])
        cache = Dict()

        new(pipe_in, pipe_out, "", Dict{String,Document}(), cache, Channel{Symbol}(64), user_pkgdir, true, false)
    end
end

function send(message, server)
    message_json = JSON.json(message)

    write_transport_layer(server.pipe_out,message_json, server.debug_mode)
end

function Base.run(server::LanguageServerInstance)
    wontload_modules = []
    @schedule begin
        for missing_module in server.user_modules
            if !(missing_module in keys(server.cache)) && !(missing_module in wontload_modules)
                updatecache(missing_module, server)
                if !(missing_module in keys(server.cache))
                    push!(wontload_modules, missing_module)
                end
            end
        end
    end

    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        request = parse(JSONRPC.Request, message)

        process(request, server)
    end
end
