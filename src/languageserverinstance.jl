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
    pipe_in
    pipe_out

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

    out_msg_queue::Channel{Any}

    function LanguageServerInstance(pipe_in, pipe_out, debug_mode::Bool = false, env_path = "", depot_path = "")
        new(
            pipe_in,
            pipe_out,
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

function send(message, server)
    message_json = JSON.json(message)

    put!(server.out_msg_queue, message_json)
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
    @async for msg in server.out_msg_queue
        try
            write_transport_layer(server.pipe_out, msg, server.debug_mode)
        catch err
            Base.display_error(stderr, err, catch_backtrace())
            rethrow(err)
        end
    end

    trigger_symbolstore_reload(server)
    
    global T
    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        
        if message===nothing
            break
        end
        
        message_dict = JSON.parse(message)
        # For now just ignore response messages
        if haskey(message_dict, "method")
            server.debug_mode && (T = time())
            request = parse(JSONRPC.Request, message_dict)
            process(request, server)
        elseif get(message_dict, "id", 0)  == -100 && haskey(message_dict, "result")
            # set format options
            update_julia_config(message_dict, server)
        end

        if isready(server.symbol_results_channel)
            server.symbol_store = take!(server.symbol_results_channel)

            roots = Document[]
            for (uri, doc) in server.documents
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

function read_transport_layer(stream, debug_mode = false)
    header_dict = Dict{String,String}()
    line = chomp(readline(stream))
    # Check whether the socket was closed
    if line == ""        
        return nothing
    end
    while length(line) > 0
        h_parts = split(line, ":")
        header_dict[chomp(h_parts[1])] = chomp(h_parts[2])
        line = chomp(readline(stream))
    end
    message_length = parse(Int, header_dict["Content-Length"])
    message_str = String(read(stream, message_length))
    debug_mode && @info "RECEIVED: $message_str"
    debug_mode && @info ""
    return message_str
end

function write_transport_layer(stream, response, debug_mode = false)
    global T
    response_utf8 = transcode(UInt8, response)
    n = length(response_utf8)
    write(stream, "Content-Length: $n\r\n\r\n")
    write(stream, response_utf8)
    debug_mode && @info "SENT: $response"
    debug_mode && @info string("TIME:", round(time()-T, sigdigits = 2))
end

