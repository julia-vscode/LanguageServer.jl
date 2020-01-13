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
            StaticLint.LintOptions()
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

    write_transport_layer(server.pipe_out, message_json, server.debug_mode)
end

"""
    run(server::LanguageServerInstance)

Run the language `server`.
"""
function Base.run(server::LanguageServerInstance)
    SymbolServer.getstore(server.symbol_server, server.env_path, server.symbol_results_channel)
    
    global T
    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        message_dict = JSON.parse(message)
        # For now just ignore response messages
        if haskey(message_dict, "method")
            server.debug_mode && (T = time())
            request = parse(JSONRPC.Request, message_dict)
            process(request, server)
        elseif get(message_dict, "id", 0)  == -100 && haskey(message_dict, "result")
            # set format options
            if length(message_dict["result"]) == length(fieldnames(DocumentFormat.FormatOptions)) + 1
                server.format_options = DocumentFormat.FormatOptions(
                    message_dict["result"][1]===nothing ? 0 : message_dict["result"][1],
                    message_dict["result"][2]===nothing ? false : message_dict["result"][2],
                    message_dict["result"][3]===nothing ? false : message_dict["result"][3],
                    message_dict["result"][4]===nothing ? false : message_dict["result"][4],
                    message_dict["result"][5]===nothing ? false : message_dict["result"][5],
                    message_dict["result"][6]===nothing ? false : message_dict["result"][6],
                    message_dict["result"][7]===nothing ? false : message_dict["result"][7],
                    message_dict["result"][8]===nothing ? false : message_dict["result"][8],
                    message_dict["result"][9]===nothing ? false : message_dict["result"][9],
                    message_dict["result"][10]===nothing ? false : message_dict["result"][10])

                x = message_dict["result"][end]
                new_run_lint_value = x===nothing ? false : true

                if new_run_lint_value != server.runlinter
                    server.runlinter = new_run_lint_value
                    for doc in values(server.documents)
                        publish_diagnostics(doc, server)
                    end
                end

            end
        end

        if isready(server.symbol_results_channel)
            server.symbol_store = take!(server.symbol_results_channel)

            # TODO should probably re-run linting

            for (uri, doc) in server.documents
                parse_all(doc, server)
            end
        end
    end
end

function serverbusy(server)
    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "method" => "window/setStatusBusy")), server.debug_mode)
end

function serverready(server)
    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "method" => "window/setStatusReady")), server.debug_mode)
end

function read_transport_layer(stream, debug_mode = false)
    header_dict = Dict{String,String}()
    line = chomp(readline(stream))
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

