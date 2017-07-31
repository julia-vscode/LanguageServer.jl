mutable struct LanguageServerInstance
    pipe_in
    pipe_out

    rootPath::String 
    documents::Dict{String,Document}
    user_modules::Channel{Tuple{Symbol,String,UnitRange{Int}}}

    debug_mode::Bool
    runlinter::Bool
    isrunning::Bool

    user_pkg_dir::String

    function LanguageServerInstance(pipe_in, pipe_out, debug_mode::Bool, user_pkg_dir::AbstractString = haskey(ENV, "JULIA_PKGDIR") ? ENV["JULIA_PKGDIR"] : joinpath(homedir(), ".julia"))
        new(pipe_in, pipe_out, "", Dict{String,Document}(), Channel{Tuple{Symbol,String,UnitRange{Int}}}(500), debug_mode, false, false, user_pkg_dir)
    end
end

function send(message, server)
    message_json = JSON.json(message)

    write_transport_layer(server.pipe_out, message_json, server.debug_mode)
end

function Base.run(server::LanguageServerInstance)
    loaded = []
    wontload = []
    @schedule begin
        for (modname, uri, loc) in server.user_modules
            if !(modname in wontload || modname in loaded) 
                try 
                    @eval import $modname
                    for (uri, doc) in server.documents
                        if doc._open_in_editor
                            doc.diagnostics = lint(doc, server).diagnostics
                            publish_diagnostics(doc, server)
                        end
                    end
                catch err
                    push!(wontload, modname)
                end
            end
        end
    end

    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        request = parse(JSONRPC.Request, message)
        server.isrunning && serverbusy(server)
        process(request, server)
        server.isrunning && serverready(server)
    end
end

function serverbusy(server)
    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "method" => "window/setStatusBusy")), server.debug_mode)
end

function serverready(server)
    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "method" => "window/setStatusReady")), server.debug_mode)
end


