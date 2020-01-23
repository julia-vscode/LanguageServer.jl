T = 0.0

"""
    LanguageServerInstance(pipe_in, pipe_out, debug=false, env="", depot="")

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
"""
mutable struct LanguageServerInstance
    jr_endpoint::JSONRPCEndpoints.JSONRPCEndpoint
    workspaceFolders::Set{String}
    documents::Dict{URI2,Document}

    debug_mode::Bool
    runlinter::Bool
    ignorelist::Set{String}
    isrunning::Bool
    
    env_path::String
    depot_path::String
    symbol_server::SymbolServer.SymbolServerInstance
    symbol_results_channel::Channel{Any}
    symbol_store::Dict{String,SymbolServer.ModuleStore}
    # ss_task::Union{Nothing,Future}
    format_options::DocumentFormat.FormatOptions
    lint_options::StaticLint.LintOptions

    combined_msg_queue::Channel{Any}

    function LanguageServerInstance(pipe_in, pipe_out, debug_mode::Bool = false, env_path = "", depot_path = "")
        new(
            JSONRPCEndpoints.JSONRPCEndpoint(pipe_in, pipe_out),
            Set{String}(),
            Dict{URI2,Document}(),
            debug_mode,
            true, 
            Set{String}(), 
            false, 
            env_path, 
            depot_path, 
            SymbolServer.SymbolServerInstance(depot_path), 
            Channel(Inf),
            deepcopy(SymbolServer.stdlibs),
            DocumentFormat.FormatOptions(), 
            StaticLint.LintOptions(),
            Channel{Any}(Inf)
        )
    end
end
function Base.display(server::LanguageServerInstance)
    println("Root: ", server.workspaceFolders)
    for (uri, d) in server.documents
        display(d)
    end
end

function trigger_symbolstore_reload(server::LanguageServerInstance)
    @async begin
        # TODO Add try catch handler that links into crash reporting
        ssi_ret, payload = SymbolServer.getstore(server.symbol_server, server.env_path)

        if ssi_ret==:success
            push!(server.symbol_results_channel, payload)
        end
    end
end

"""
    run(server::LanguageServerInstance)

Run the language `server`.
"""
function Base.run(server::LanguageServerInstance)
    run(server.jr_endpoint)

    trigger_symbolstore_reload(server)

    @async begin
        while true
            msg = JSONRPCEndpoints.get_next_message(server.jr_endpoint)
            put!(server.combined_msg_queue, (type=:clientmsg, msg=msg))
        end
    end

    @async begin
        while true
            msg = take!(server.symbol_results_channel)
            put!(server.combined_msg_queue, (type=:symservmsg, msg=msg))
        end
    end
        
    while true
        message = take!(server.combined_msg_queue)

        if message.type==:clientmsg
            msg = message.msg                

            request = parse(JSONRPC.Request, msg)

            try
                res = process(request, server)

                if request.id!=nothing
                    send_success_response(server.jr_endpoint, msg, res)
                end
            catch err
                if request.id!=nothing
                    # TODO Make sure this is right
                    send_error_response(server.jr_endpoint, msg, res)
                end
            end        
        elseif message.type==:symservmsg
            msg = message.msg

            server.symbol_store = msg

            # TODO should probably re-run linting

            for (uri, doc) in server.documents
                parse_all(doc, server)
            end
        end
    end
end




