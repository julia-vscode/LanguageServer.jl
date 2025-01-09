"""
    LanguageServerInstance(pipe_in, pipe_out, env="", depot="", err_handler=nothing, symserver_store_path=nothing)

Construct an instance of the language server.

Once the instance is `run`, it will read JSON-RPC from `pipe_out` and
write JSON-RPC from `pipe_in` according to the [language server
specification](https://microsoft.github.io/language-server-protocol/specifications/specification-3-14/).
For normal usage, the language server can be instantiated with
`LanguageServerInstance(stdin, stdout, false, "/path/to/environment")`.

# Arguments
- `pipe_in::IO`: Pipe to read JSON-RPC from.
- `pipe_out::IO`: Pipe to write JSON-RPC to.
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
    jr_endpoint::Union{JSONRPC.JSONRPCEndpoint,Nothing}
    workspaceFolders::Set{String}
    _documents::Dict{URI,Document}

    env_path::String
    depot_path::String
    symbol_server::SymbolServer.SymbolServerInstance
    symbol_results_channel::Channel{Any}
    global_env::StaticLint.ExternalEnv
    roots_env_map::Dict{Document,StaticLint.ExternalEnv}
    symbol_store_ready::Bool

    runlinter::Bool
    lint_options::StaticLint.LintOptions
    lint_missingrefs::Symbol
    lint_disableddirs::Vector{String}
    completion_mode::Symbol
    inlay_hints::Bool
    inlay_hints_variable_types::Bool
    inlay_hints_parameter_names::Symbol

    combined_msg_queue::Channel{Any}

    err_handler::Union{Nothing,Function}

    status::Symbol

    number_of_outstanding_symserver_requests::Int
    symserver_use_download::Bool

    current_symserver_progress_token::Union{Nothing,String}

    clientcapability_window_workdoneprogress::Bool
    clientcapability_workspace_didChangeConfiguration::Bool
    # Can probably drop the above 2 and use the below.
    clientCapabilities::Union{ClientCapabilities,Missing}
    clientInfo::Union{InfoParams,Missing}
    initialization_options::Union{Missing,Dict}

    editor_pid::Union{Nothing,Int}
    shutdown_requested::Bool

    workspace::JuliaWorkspace
    # This has one entry for each open file (in the LSP sense). The key is the uri fo the file
    # and the value is the version of the file that the LS client sent.
    _open_file_versions::Dict{URI,Int}
    _files_from_disc::Dict{URI,JuliaWorkspaces.TextFile}
    # This is a list of files that should be kept around that are potentially not in a workspace
    # folder. Primarily for projects and manifests outside of the workspace.
    _extra_tracked_files::Vector{URI}

    _send_request_metrics::Bool

    function LanguageServerInstance(@nospecialize(pipe_in), @nospecialize(pipe_out), env_path="", depot_path="", err_handler=nothing, symserver_store_path=nothing, download=true, symbolcache_upstream = nothing, julia_exe::Union{NamedTuple{(:path,:version),Tuple{String,VersionNumber}},Nothing}=nothing)
        endpoint = JSONRPC.JSONRPCEndpoint(pipe_in, pipe_out, err_handler)
        jw = JuliaWorkspace()
        # if hasfield(typeof(jw.runtime), :performance_tracing_callback)
        #     jw.runtime.performance_tracing_callback = (name, start_time, duration) -> begin
        #         if g_operationId[] != "" && endpoint.status === :running
        #             JSONRPC.send(
        #                 endpoint,
        #                 telemetry_event_notification_type,
        #                 Dict(
        #                     "command" => "request_metric",
        #                     "operationId" => string(uuid4()),
        #                     "operationParentId" => g_operationId[],
        #                     "name" => name,
        #                     "duration" => duration,
        #                     "time" => string(Dates.unix2datetime(start_time), "Z")
        #                 )
        #             )
        #         end
        #     end
        # end

        new(
            endpoint,
            Set{String}(),
            Dict{URI,Document}(),
            env_path,
            depot_path,
            SymbolServer.SymbolServerInstance(depot_path, symserver_store_path, julia_exe; symbolcache_upstream=symbolcache_upstream),
            Channel(Inf),
            StaticLint.ExternalEnv(deepcopy(SymbolServer.stdlibs), SymbolServer.collect_extended_methods(SymbolServer.stdlibs), collect(keys(SymbolServer.stdlibs))),
            Dict(),
            false,
            true,
            StaticLint.LintOptions(),
            :all,
            LINT_DIABLED_DIRS,
            :qualify, # options: :import or :qualify, anything else turns this off
            false,
            true,
            :literals,
            Channel{Any}(Inf),
            err_handler,
            :created,
            0,
            download,
            nothing,
            false,
            false,
            missing,
            missing,
            missing,
            nothing,
            false,
            jw,
            Dict{URI,Int}(),
            Dict{URI,JuliaWorkspaces.TextFile}(),
            URI[],
            false
        )
    end
end
function Base.display(server::LanguageServerInstance)
    println(stderr, "Root: ", server.workspaceFolders)
    for d in getdocuments_value(server)
        display(d)
    end
end

function hasdocument(server::LanguageServerInstance, uri::URI)
    return haskey(server._documents, uri)
end

function getdocument(server::LanguageServerInstance, uri::URI)
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

function setdocument!(server::LanguageServerInstance, uri::URI, doc::Document)
    server._documents[uri] = doc
end

function deletedocument!(server::LanguageServerInstance, uri::URI)
    doc = getdocument(server, uri)
    StaticLint.clear_meta(getcst(doc))
    delete!(server._documents, uri)

    for d in getdocuments_value(server)
        if getroot(d) === doc
            setroot(d, d)
            semantic_pass(getroot(d))
        end
    end
end

function create_symserver_progress_ui(server)
    if server.clientcapability_window_workdoneprogress
        token = string(uuid4())
        server.current_symserver_progress_token = token
        JSONRPC.send(server.jr_endpoint, window_workDoneProgress_create_request_type, WorkDoneProgressCreateParams(token))

        JSONRPC.send(
            server.jr_endpoint,
            progress_notification_type,
            ProgressParams(token, WorkDoneProgressBegin("Julia", missing, "Starting async tasks...", missing))
        )
    end
end

function destroy_symserver_progress_ui(server)
    if server.clientcapability_window_workdoneprogress && server.current_symserver_progress_token !== nothing
        progress_token = server.current_symserver_progress_token
        server.current_symserver_progress_token = nothing
        JSONRPC.send(
            server.jr_endpoint,
            progress_notification_type,
            ProgressParams(progress_token, WorkDoneProgressEnd(missing))
        )
    end
end

function trigger_symbolstore_reload(server::LanguageServerInstance)
    server.symbol_store_ready = false
    if server.number_of_outstanding_symserver_requests == 0 && server.status == :running
        create_symserver_progress_ui(server)
    end
    server.number_of_outstanding_symserver_requests += 1

    if server.symserver_use_download
        @debug "Will download symbol server caches for this instance."
    end

    @async try
        ssi_ret, payload = SymbolServer.getstore(
            server.symbol_server,
            server.env_path,
            function (msg, percentage=missing)
                if server.clientcapability_window_workdoneprogress && server.current_symserver_progress_token !== nothing
                    msg = ismissing(percentage) ? msg : string(msg, " ($percentage%)")
                    JSONRPC.send(
                        server.jr_endpoint,
                        progress_notification_type,
                        ProgressParams(server.current_symserver_progress_token, WorkDoneProgressReport(missing, msg, missing))
                    )
                end
                @info msg
            end,
            server.err_handler,
            download=server.symserver_use_download
        )

        server.number_of_outstanding_symserver_requests -= 1

        if server.number_of_outstanding_symserver_requests == 0
            destroy_symserver_progress_ui(server)
        end

        if ssi_ret == :success
            push!(server.symbol_results_channel, payload)
        elseif ssi_ret == :failure
            error_payload = Dict(
                "command" => "symserv_crash",
                "name" => "LSSymbolServerFailure",
                "message" => payload === nothing ? "" : String(take!(payload)),
                "stacktrace" => "")
            JSONRPC.send(
                server.jr_endpoint,
                telemetry_event_notification_type,
                error_payload
            )
        elseif ssi_ret == :package_load_crash
            error_payload = Dict(
                "command" => "symserv_pkgload_crash",
                "name" => payload.package_name,
                "message" => payload.stderr === nothing ? "" : String(take!(payload.stderr)))
            JSONRPC.send(
                server.jr_endpoint,
                telemetry_event_notification_type,
                error_payload
            )
        end
        server.symbol_store_ready = true
    catch err
        bt = catch_backtrace()
        if server.err_handler !== nothing
            server.err_handler(err, bt)
        else
            Base.display_error(stderr, err, bt)
        end
    end
end

# Set to true to reload request handler functions with Revise (requires Revise loaded in Main)
const USE_REVISE = Ref(false)

function request_wrapper(func, server::LanguageServerInstance)
    return function (conn, params)
        if server.shutdown_requested
            # it's fine to always return a value here, even for notifications, because
            # JSONRPC discards it anyways in that case
            return JSONRPC.JSONRPCError(
                -32600,
                "LS shutdown was requested.",
                nothing
            )
        end
        if USE_REVISE[] && isdefined(Main, :Revise)
            try
                Main.Revise.revise()
            catch e
                @warn "Reloading with Revise failed" exception = e
            end
            Base.invokelatest(func, params, server, conn)
        else
            func(params, server, conn)
        end
    end
end

JSONRPC.@message_dispatcher dispatch_msg begin
    textDocument_codeAction_request_type => (conn, params, server) -> textDocument_codeAction_request(params, server, conn)
    workspace_executeCommand_request_type => (conn, params, server) -> workspace_executeCommand_request(params, server, conn)
    textDocument_completion_request_type => (conn, params, server) -> textDocument_completion_request(params, server, conn)
    textDocument_signatureHelp_request_type => (conn, params, server) -> textDocument_signatureHelp_request(params, server, conn)
    textDocument_definition_request_type => (conn, params, server) -> textDocument_definition_request(params, server, conn)
    textDocument_formatting_request_type => (conn, params, server) -> textDocument_formatting_request(params, server, conn)
    textDocument_range_formatting_request_type => (conn, params, server) -> textDocument_range_formatting_request(params, server, conn)
    textDocument_references_request_type => (conn, params, server) -> textDocument_references_request(params, server, conn)
    textDocument_rename_request_type => (conn, params, server) -> textDocument_rename_request(params, server, conn)
    textDocument_prepareRename_request_type => (conn, params, server) -> textDocument_prepareRename_request(params, server, conn)
    textDocument_documentSymbol_request_type => (conn, params, server) -> textDocument_documentSymbol_request(params, server, conn)
    textDocument_documentHighlight_request_type => (conn, params, server) -> textDocument_documentHighlight_request(params, server, conn)
    julia_getModuleAt_request_type => (conn, params, server) -> julia_getModuleAt_request(params, server, conn)
    julia_getDocAt_request_type => (conn, params, server) -> julia_getDocAt_request(params, server, conn)
    textDocument_hover_request_type => (conn, params, server) -> textDocument_hover_request(params, server, conn)
    initialize_request_type => (conn, params, server) -> initialize_request(params, server, conn)
    initialized_notification_type => (conn, params, server) -> initialized_notification(params, server, conn)
    shutdown_request_type => (conn, params, server) -> shutdown_request(params, server, conn)
    cancel_notification_type => (conn, params, server) -> cancel_notification(params, server, conn)
    setTrace_notification_type => (conn, params, server) -> setTrace_notification(params, server, conn)
    setTraceNotification_notification_type => (conn, params, server) -> setTraceNotification_notification(params, server, conn)
    julia_getCurrentBlockRange_request_type => (conn, params, server) -> julia_getCurrentBlockRange_request(params, server, conn)
    julia_activateenvironment_notification_type => (conn, params, server) -> julia_activateenvironment_notification(params, server, conn)
    textDocument_didOpen_notification_type => (conn, params, server) -> textDocument_didOpen_notification(params, server, conn)
    textDocument_didClose_notification_type => (conn, params, server) -> textDocument_didClose_notification(params, server, conn)
    textDocument_didSave_notification_type => (conn, params, server) -> textDocument_didSave_notification(params, server, conn)
    textDocument_willSave_notification_type => (conn, params, server) -> textDocument_willSave_notification(params, server, conn)
    textDocument_willSaveWaitUntil_request_type => (conn, params, server) -> textDocument_willSaveWaitUntil_request(params, server, conn)
    textDocument_didChange_notification_type => (conn, params, server) -> textDocument_didChange_notification(params, server, conn)
    workspace_didChangeWatchedFiles_notification_type => (conn, params, server) -> workspace_didChangeWatchedFiles_notification(params, server, conn)
    workspace_didChangeConfiguration_notification_type => (conn, params, server) -> workspace_didChangeConfiguration_notification(params, server, conn)
    workspace_didChangeWorkspaceFolders_notification_type => (conn, params, server) -> workspace_didChangeWorkspaceFolders_notification(params, server, conn)
    workspace_symbol_request_type => (conn, params, server) -> workspace_symbol_request(params, server, conn)
    julia_refreshLanguageServer_notification_type => (conn, params, server) -> julia_refreshLanguageServer_notification(params, server, conn)
    julia_getDocFromWord_request_type => (conn, params, server) -> julia_getDocFromWord_request(params, server, conn)
    textDocument_selectionRange_request_type => (conn, params, server) -> textDocument_selectionRange_request(params, server, conn)
    textDocument_documentLink_request_type => (conn, params, server) -> textDocument_documentLink_request(params, server, conn)
    textDocument_inlayHint_request_type => (conn, params, server) -> textDocument_inlayHint_request(params, server, conn)
    julia_get_test_env_request_type => (conn, params, server) -> julia_get_test_env_request(params, server, conn)

    # The exit notification message should not be wrapped in request_wrapper (which checks
    # if the server have been requested to be shut down). Instead, this message needs to be
    # handled directly.
    exit_notification_type => (conn, params, server) -> exit_notification(params, server, conn)
end

"""
    run(server::LanguageServerInstance)

Run the language `server`.
"""
function Base.run(server::LanguageServerInstance; timings = [])
    did_show_timer = Ref(false)
    add_timer_message!(did_show_timer, timings, "LS startup started")

    server.status = :started

    run(server.jr_endpoint)
    @debug "Connected at $(round(Int, time()))"
    add_timer_message!(did_show_timer, timings, "connection established")

    trigger_symbolstore_reload(server)

    poll_editor_pid(server)

    @async try
        @debug "LS: Starting client listener task."
        add_timer_message!(did_show_timer, timings, "(async) listening to client events")
        while true
            msg = JSONRPC.get_next_message(server.jr_endpoint)
            put!(server.combined_msg_queue, (type=:clientmsg, msg=msg))
        end
    catch err
        bt = catch_backtrace()
        if server.err_handler !== nothing
            server.err_handler(err, bt)
        else
            @warn "LS: An error occurred in the client listener task. This may be normal." exception=(err, bt)
        end
    finally
        if isopen(server.combined_msg_queue)
            put!(server.combined_msg_queue, (type=:close,))
            close(server.combined_msg_queue)
        end
        @debug "LS: Client listener task done."
    end
    yield()

    @async try
        @debug "LS: Starting symbol server listener task."
        add_timer_message!(did_show_timer, timings, "(async) listening to symbol server events")
        while true
            msg = take!(server.symbol_results_channel)
            put!(server.combined_msg_queue, (type=:symservmsg, msg=msg))
        end
    catch err
        bt = catch_backtrace()
        if server.err_handler !== nothing
            server.err_handler(err, bt)
        else
            @error "LS: Queue op failed" ex=(err, bt)
        end
    finally
        if isopen(server.combined_msg_queue)
            put!(server.combined_msg_queue, (type=:close,))
            close(server.combined_msg_queue)
        end
        @debug "LS: Symbol server listener task done."
    end
    yield()

    @debug "async tasks started at $(round(Int, time()))"  

    @debug "Starting event listener loop at $(round(Int, time()))"
    add_timer_message!(did_show_timer, timings, "starting combined listener")

    while true
        message = take!(server.combined_msg_queue)

        if message.type == :close
            @debug "Shutting down server instance."
            return
        elseif message.type == :clientmsg
            msg = message.msg

            add_timer_message!(did_show_timer, timings, msg)

            g_operationId[] = string(uuid4())

            start_time = string(Dates.unix2datetime(time()), "Z")
            tic = time_ns()
            dispatch_msg(server.jr_endpoint, msg, server)
            toc = time_ns()
            duration = (toc - tic) / 1e+6

            if server._send_request_metrics
                JSONRPC.send(
                    server.jr_endpoint,
                    telemetry_event_notification_type,
                    Dict(
                    "command" => "request_metric",
                    "operationId" => g_operationId[],
                    "name" => msg["method"],
                    "time" => start_time,
                    "duration" => duration)
                )
            end
        elseif message.type == :symservmsg
            @debug "Received new data from Julia Symbol Server."

            server.global_env.symbols = message.msg
            add_timer_message!(did_show_timer, timings, "symbols received")
            server.global_env.extended_methods = SymbolServer.collect_extended_methods(server.global_env.symbols)
            add_timer_message!(did_show_timer, timings, "extended methods computed")
            server.global_env.project_deps = collect(keys(server.global_env.symbols))
            add_timer_message!(did_show_timer, timings, "project deps computed")

            # redo roots_env_map
            for (root, _) in server.roots_env_map
                @debug "resetting get_env_for_root"
                newenv = get_env_for_root(root, server)
                if newenv === nothing
                    delete!(server.roots_env_map, root)
                else
                    server.roots_env_map[root] = newenv
                end
            end
            add_timer_message!(did_show_timer, timings, "env map computed")

            @debug "Linting started at $(round(Int, time()))"

            relintserver(server)

            @debug "Linting finished at $(round(Int, time()))"
            add_timer_message!(did_show_timer, timings, "initial lint done")
        end
    end
end

function relintserver(server)
    marked_versions = mark_current_diagnostics_testitems(server.workspace)

    roots = Set{Document}()
    documents = collect(getdocuments_value(server))
    for doc in documents
        StaticLint.clear_meta(getcst(doc))
        set_doc(getcst(doc), doc)
    end
    for doc in documents
        # only do a pass on documents once
        root = getroot(doc)
        if !(root in roots)
            if get_language_id(root) in ("julia", "markdown", "juliamarkdown")
                push!(roots, root)
                semantic_pass(root)
            end
        end
    end
    for doc in documents
        if get_language_id(doc) in ("julia", "markdown", "juliamarkdown")
            lint!(doc, server)
        end
    end
    publish_diagnostics_testitems(server, marked_versions, get_uri.(documents))
end
