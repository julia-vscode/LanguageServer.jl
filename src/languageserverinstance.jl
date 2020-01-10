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
    symbol_server::Union{Nothing,SymbolServer.SymbolServerProcess}
    ss_task::Union{Nothing,Future}
    format_options::DocumentFormat.FormatOptions
    lint_options::StaticLint.LintOptions

    function LanguageServerInstance(pipe_in, pipe_out, debug_mode::Bool = false, env_path = "", depot_path = "")
        new(pipe_in, pipe_out, Set{String}(), Dict{URI2,Document}(), debug_mode, true, Set{String}(), false, env_path, depot_path, nothing, nothing, DocumentFormat.FormatOptions(), StaticLint.LintOptions())
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

function init_symserver(server::LanguageServerInstance)
    wid = last(procs())
    env_path = server.env_path
    server.symbol_server = SymbolServer.SymbolServerProcess()
    server.ss_task = @spawnat wid begin 
        empty!(Base.DEPOT_PATH)
        push!(Base.DEPOT_PATH, server.depot_path)
        SymbolServer.Pkg.activate(env_path)
        SymbolServer.Pkg.Types.Context()
    end
end


"""
    run(server::LanguageServerInstance)

Run the language `server`.
"""
function Base.run(server::LanguageServerInstance)
    init_symserver(server)
    
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

        if server.ss_task !== nothing && isready(server.ss_task)
            res = fetch(server.ss_task)
            server.ss_task = nothing
            if res isa Vector{Base.UUID}
                uuids = res
                if !isempty(uuids)
                    for uuid in uuids
                        SymbolServer.disc_load(server.symbol_server.context, uuid, server.symbol_server.depot)
                    end
                end
                repass_all(server)
            elseif res isa SymbolServer.Pkg.Types.Context
                # Clear all meta info from cst to ensure no lingering links to packages
                clear_all_meta(server)
                # Remove all non base/core packages
                if server.symbol_server isa SymbolServerProcess
                    for (n, _) in server.symbol_server.depot
                        if !(n in ("Base", "Core"))
                            delete!(server.symbol_server.depot, n)
                        end
                    end
                end
                server.symbol_server.context = res
                missing_pkgs = SymbolServer.disc_load_project(server.symbol_server)
                if !isempty(missing_pkgs)
                    pkg_uuids = collect(keys(missing_pkgs))
                    server.debug_mode && @info "Missing or outdated package caches: ", collect(missing_pkgs)
                    wid = last(procs())
                    server.ss_task = @spawnat wid SymbolServer.cache_packages_and_save(server.symbol_server.context, pkg_uuids)
                end
                repass_all(server)
            end
        end
    end
end

function clear_all_meta(server)
    for (uri, doc) in server.documents
        StaticLint.clear_meta(getcst(doc))
    end
end

function repass_all(server::LanguageServerInstance)
    roots = Document[]
    for (uri, doc) in server.documents
        if !(getroot(doc) in roots)
            push!(roots, getroot(doc))
            scopepass(getroot(doc))
        end
    end

    for (uri, doc) in server.documents
        StaticLint.check_all(getcst(doc), server.lint_options, server)
        empty!(doc.diagnostics)
        mark_errors(doc, doc.diagnostics)
        publish_diagnostics(doc, server)
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

