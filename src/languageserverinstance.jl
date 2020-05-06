T = 0.0

"""
    LanguageServerInstance(pipe_in, pipe_out, debug=false, env="", depot="", err_handler=nothing, symserver_store_path=nothing)

Construct an instance of the language server.

Once the instance is `run`, it will read JSON-RPC from `pipe_out` and
write JSON-RPC from `pipe_in` according to the [language server
specification](https://microsoft.github.io/language-server-protocol/specifications/specification-3-14/).
For normal usage, the language server can be instantiated with
`LanguageServerInstance(stdin, stdout, false, "/path/to/environment")`.

# Arguments
- `pipe_in::IO`: Pipe to read JSON-RPC from.
- `pipe_out::IO`: Pipe to write JSON-RPC to.
- `debug::Bool`: Whether to log debugging information with `Base.CoreLogging`.
- `env::String`: Path to the
  [environment](https://docs.julialang.org/en/v1.2/manual/code-loading/#Environments-1)
  for which the language server is running. An empty string uses julia's
  default environment.
- `depot::String`: Sets the
  [`JULIA_DEPOT_PATH`](https://docs.julialang.org/en/v1.2/manual/environment-variables/#JULIA_DEPOT_PATH-1)
  where the language server looks for packages required in `env`.
- `err_handler::Union{Nothing,Function}`: If not `nothing`, catch all errors and pass them to an error handler
  function with signature `err_handler(err, bt)`. Mostly used for the VS Code crash reporting implementation.
- `symserver_store_path::Union{Nothing,String}`: if `nothing` is passed, the symbol server cash is stored in
  a folder in the package. If an absolute path is passed, the symbol server will store the cache files in that
  path. The path must exist on disc before this is called.
"""
mutable struct LanguageServerInstance
    jr_endpoint::JSONRPCEndpoints.JSONRPCEndpoint
    workspaceFolders::Set{String}
    _documents::Dict{URI2,Document}

    debug_mode::Bool
    runlinter::Bool
    ignorelist::Set{String}
    isrunning::Bool
    
    env_path::String
    depot_path::String
    symbol_server::SymbolServer.SymbolServerInstance
    symbol_results_channel::Channel{Any}
    symbol_store::Dict{Symbol,SymbolServer.ModuleStore}
    symbol_extends::Dict{SymbolServer.VarRef,Vector{SymbolServer.VarRef}}
    symbol_store_ready::Bool
    # ss_task::Union{Nothing,Future}
    format_options::DocumentFormat.FormatOptions
    lint_options::StaticLint.LintOptions

    combined_msg_queue::Channel{Any}

    err_handler::Union{Nothing,Function}

    status::Symbol

    number_of_outstanding_symserver_requests::Int

    current_symserver_progress_token::Union{Nothing,String}

    clientcapability_window_workdoneprogress::Bool
    clientcapability_workspace_didChangeConfiguration::Bool

    function LanguageServerInstance(pipe_in, pipe_out, debug_mode::Bool = false, env_path = "", depot_path = "", err_handler=nothing, symserver_store_path=nothing)
        new(
            JSONRPCEndpoints.JSONRPCEndpoint(pipe_in, pipe_out, err_handler),
            Set{String}(),
            Dict{URI2,Document}(),
            debug_mode,
            true, 
            Set{String}(), 
            false, 
            env_path, 
            depot_path, 
            SymbolServer.SymbolServerInstance(depot_path, symserver_store_path), 
            Channel(Inf),
            deepcopy(SymbolServer.stdlibs),
            SymbolServer.collect_extended_methods(SymbolServer.stdlibs),
            false,
            DocumentFormat.FormatOptions(), 
            StaticLint.LintOptions(),
            Channel{Any}(Inf),
            err_handler,
            :created,
            0,
            nothing,
            false,
            false
        )
    end
end
function Base.display(server::LanguageServerInstance)
    println("Root: ", server.workspaceFolders)
    for d in getdocuments_value(server)
        display(d)
    end
end

function hasdocument(server::LanguageServerInstance, uri::URI2)
    return haskey(server._documents, uri)
end

function getdocument(server::LanguageServerInstance, uri::URI2)
    return server._documents[uri]
end

function getdocuments_key(server::LanguageServerInstance)
    return keys(server._documents)
end

function getdocuments_pair(server::LanguageServerInstance)
    return pairs(server._documents)
end

function getdocuments_value(server::LanguageServerInstance)
    return values(server._documents)
end

function setdocument!(server::LanguageServerInstance, uri::URI2, doc::Document)
    server._documents[uri] = doc
end

function deletedocument!(server::LanguageServerInstance, uri::URI2)
    doc = getdocument(uri)

    delete!(server._documents, uri)

    for d in getdocuments_value(server)
        if d.root===doc
            d.root = nothing
            scopepass(d, d)
        end
    end
end

function create_symserver_progress_ui(server)
    if server.clientcapability_window_workdoneprogress
        server.current_symserver_progress_token = string(uuid4())
        response = JSONRPCEndpoints.send_request(server.jr_endpoint, "window/workDoneProgress/create", Dict("token" => server.current_symserver_progress_token))

        JSONRPCEndpoints.send_notification(server.jr_endpoint, "\$/progress", Dict("token" => server.current_symserver_progress_token, "value" => Dict("kind"=>"begin", "title"=>"Julia Language Server", "message"=>"Indexing packages...")))
    end
end

function destroy_symserver_progress_ui(server)
    if server.clientcapability_window_workdoneprogress && server.current_symserver_progress_token!==nothing
        progress_token = server.current_symserver_progress_token
        server.current_symserver_progress_token = nothing
        JSONRPCEndpoints.send_notification(server.jr_endpoint, "\$/progress", Dict("token" => progress_token, "value" => Dict("kind"=>"end")))
    end
end

function trigger_symbolstore_reload(server::LanguageServerInstance)
    server.symbol_store_ready = false
    if server.number_of_outstanding_symserver_requests==0 && server.status==:running
        create_symserver_progress_ui(server)
    end
    server.number_of_outstanding_symserver_requests += 1

    @async try
        # TODO Add try catch handler that links into crash reporting
        ssi_ret, payload = SymbolServer.getstore(
            server.symbol_server,
            server.env_path,
            i-> if server.clientcapability_window_workdoneprogress && server.current_symserver_progress_token!==nothing
                JSONRPCEndpoints.send_notification(server.jr_endpoint, "\$/progress", Dict("token" => server.current_symserver_progress_token, "value" => Dict("kind"=>"report", "message"=>"Indexing $i...")))
            end,
            server.err_handler
        )
        server.symbol_extends = SymbolServer.collect_extended_methods(server.symbol_store)

        server.number_of_outstanding_symserver_requests -= 1

        if server.number_of_outstanding_symserver_requests==0
            destroy_symserver_progress_ui(server)
        end

        if ssi_ret==:success
            push!(server.symbol_results_channel, payload)
        elseif ssi_ret==:failure
            error_payload = Dict(
                "command"=>"symserv_crash",
                "name"=>"LSSymbolServerFailure",
                "message"=>payload===nothing ? "" : String(take!(payload)),
                "stacktrace"=>"")
            JSONRPCEndpoints.send_notification(server.jr_endpoint, "telemetry/event", error_payload)
        elseif ssi_ret==:package_load_crash
            error_payload = Dict(
                "command"=>"symserv_pkgload_crash",
                "name"=>payload.package_name,
                "message"=>payload.stderr===nothing ? "" : String(take!(payload.stderr)))
            JSONRPCEndpoints.send_notification(server.jr_endpoint, "telemetry/event", error_payload)
        end
        server.symbol_store_ready = true
    catch err
        bt = catch_backtrace()
        if server.err_handler!==nothing
            server.err_handler(err, bt)
        else
            Base.display_error(stderr, err, bt)
        end
    end
end

"""
    run(server::LanguageServerInstance)

Run the language `server`.
"""
function Base.run(server::LanguageServerInstance)
    server.status=:started

    run(server.jr_endpoint)

    trigger_symbolstore_reload(server)

    @async try
        while true
            msg = JSONRPCEndpoints.get_next_message(server.jr_endpoint)
            put!(server.combined_msg_queue, (type=:clientmsg, msg=msg))
        end
    catch err
        bt = catch_backtrace()
        if server.err_handler!==nothing
            server.err_handler(err, bt)
        else
            Base.display_error(stderr, err, bt)
        end
    end

    @async try
        while true
            msg = take!(server.symbol_results_channel)
            put!(server.combined_msg_queue, (type=:symservmsg, msg=msg))
        end
    catch err
        bt = catch_backtrace()
        if server.err_handler!==nothing
            server.err_handler(err, bt)
        else
            Base.display_error(stderr, err, bt)
        end
    end
        
    while true
        message = take!(server.combined_msg_queue)

        if message.type==:clientmsg
            msg = message.msg                

            request = parse(JSONRPC.Request, msg)

            res = process(request, server)

            if request.id!=nothing
                JSONRPCEndpoints.send_success_response(server.jr_endpoint, msg, res)
            end
        elseif message.type==:symservmsg
            @info "Received new data from Julia Symbol Server."
            msg = message.msg

            server.symbol_store = msg
            roots = Document[]
            for doc in getdocuments_value(server)
                # only do a pass on documents once
                root = getroot(doc)
                if !(root in roots)
                    push!(roots, root)
                    scopepass(root, doc)
                end

                StaticLint.check_all(getcst(doc), server.lint_options, server)
                empty!(doc.diagnostics)
                mark_errors(doc, doc.diagnostics)
                publish_diagnostics(doc, server)
            end
        end
    end
end


