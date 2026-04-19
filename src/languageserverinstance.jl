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

    env_path::String

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
    # Tracks which files are workspace files (found on disc in a workspace folder).
    _workspace_files::Set{URI}
    # This is a list of files that should be kept around that are potentially not in a workspace
    # folder. Primarily for projects and manifests outside of the workspace.
    _extra_tracked_files::Vector{URI}

    # Indirect files: URIs requested by JW (via include traversal) for which we
    # have registered an LSP file watcher. Maps URI -> registration id so we can
    # unregister later. Reconciled in `reconcile_indirect_file_watchers`.
    _watched_indirect_files::Dict{URI,String}

    _send_request_metrics::Bool

    trace_value::Threads.Atomic{Int}

    function LanguageServerInstance(@nospecialize(pipe_in), @nospecialize(pipe_out), env_path="", err_handler=nothing, symserver_store_path=nothing, download=true, symbolcache_upstream = nothing, julia_exe::Union{NamedTuple{(:path,:version),Tuple{String,VersionNumber}},Nothing}=nothing)
        endpoint = JSONRPC.JSONRPCEndpoint(pipe_in, pipe_out)

        server_ref = Ref{LanguageServerInstance}()
        _progress_cb = _create_deferred_progress_callback(server_ref)

        jw = JuliaWorkspace(;dynamic=JuliaWorkspaces.DynamicIndexingOnly, store_path=symserver_store_path, progress_callback=_progress_cb)

        server = new(
            endpoint,
            Set{String}(),
            env_path,
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
            Set{URI}(),
            URI[],
            Dict{URI,String}(),
            false,
            Threads.Atomic{Int}(Int(lsp_trace_off))
        )
        server_ref[] = server
        return server
    end
end
function Base.display(server::LanguageServerInstance)
    println(stderr, "Root: ", server.workspaceFolders)
    for uri in JuliaWorkspaces.get_text_files(server.workspace)
        println(stderr, "  ", uri)
    end
end

# Set to true to reload request handler functions with Revise (requires Revise loaded in Main)
const USE_REVISE = Ref(false)

function request_wrapper(func, server::LanguageServerInstance)
    return function (conn, params, token)
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

function notification_wrapper(func, server::LanguageServerInstance)
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

"""
    run(server::LanguageServerInstance)

Run the language `server`.
"""
function Base.run(server::LanguageServerInstance; timings = [])
    did_show_timer = Ref(false)
    add_timer_message!(did_show_timer, timings, "LS startup started")

    server.status = :started

    JSONRPC.start(server.jr_endpoint)
    @debug "Connected at $(round(Int, time()))"
    add_timer_message!(did_show_timer, timings, "connection established")

    new_logger = LoggingExtras.TeeLogger(
        Logging.current_logger(),
        LSPTraceLogger(server)
    )

    Logging.with_logger(new_logger) do

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

        @debug "async tasks started at $(round(Int, time()))"

        msg_dispatcher = JSONRPC.MsgDispatcher()

        msg_dispatcher[textDocument_codeAction_request_type] = request_wrapper(textDocument_codeAction_request, server)
        msg_dispatcher[workspace_executeCommand_request_type] = request_wrapper(workspace_executeCommand_request, server)
        msg_dispatcher[textDocument_completion_request_type] = request_wrapper(textDocument_completion_request, server)
        msg_dispatcher[textDocument_signatureHelp_request_type] = request_wrapper(textDocument_signatureHelp_request, server)
        msg_dispatcher[textDocument_definition_request_type] = request_wrapper(textDocument_definition_request, server)
        msg_dispatcher[textDocument_formatting_request_type] = request_wrapper(textDocument_formatting_request, server)
        msg_dispatcher[textDocument_range_formatting_request_type] = request_wrapper(textDocument_range_formatting_request, server)
        msg_dispatcher[textDocument_references_request_type] = request_wrapper(textDocument_references_request, server)
        msg_dispatcher[textDocument_rename_request_type] = request_wrapper(textDocument_rename_request, server)
        msg_dispatcher[textDocument_prepareRename_request_type] = request_wrapper(textDocument_prepareRename_request, server)
        msg_dispatcher[textDocument_documentSymbol_request_type] = request_wrapper(textDocument_documentSymbol_request, server)
        msg_dispatcher[textDocument_documentHighlight_request_type] = request_wrapper(textDocument_documentHighlight_request, server)
        msg_dispatcher[julia_getModuleAt_request_type] = request_wrapper(julia_getModuleAt_request, server)
        msg_dispatcher[julia_getDocAt_request_type] = request_wrapper(julia_getDocAt_request, server)
        msg_dispatcher[textDocument_hover_request_type] = request_wrapper(textDocument_hover_request, server)
        msg_dispatcher[initialize_request_type] = request_wrapper(initialize_request, server)
        msg_dispatcher[initialized_notification_type] = notification_wrapper(initialized_notification, server)
        msg_dispatcher[shutdown_request_type] = request_wrapper(shutdown_request, server)
        msg_dispatcher[setTrace_notification_type] = notification_wrapper(setTrace_notification, server)
        msg_dispatcher[julia_getCurrentBlockRange_request_type] = request_wrapper(julia_getCurrentBlockRange_request, server)
        msg_dispatcher[julia_activateenvironment_notification_type] = notification_wrapper(julia_activateenvironment_notification, server)
        msg_dispatcher[textDocument_didOpen_notification_type] = notification_wrapper(textDocument_didOpen_notification, server)
        msg_dispatcher[textDocument_didClose_notification_type] = notification_wrapper(textDocument_didClose_notification, server)
        msg_dispatcher[textDocument_didSave_notification_type] = notification_wrapper(textDocument_didSave_notification, server)
        msg_dispatcher[textDocument_willSave_notification_type] = notification_wrapper(textDocument_willSave_notification, server)
        msg_dispatcher[textDocument_willSaveWaitUntil_request_type] = request_wrapper(textDocument_willSaveWaitUntil_request, server)
        msg_dispatcher[textDocument_didChange_notification_type] = notification_wrapper(textDocument_didChange_notification, server)
        msg_dispatcher[workspace_didChangeWatchedFiles_notification_type] = notification_wrapper(workspace_didChangeWatchedFiles_notification, server)
        msg_dispatcher[workspace_didChangeConfiguration_notification_type] = notification_wrapper(workspace_didChangeConfiguration_notification, server)
        msg_dispatcher[workspace_didChangeWorkspaceFolders_notification_type] = notification_wrapper(workspace_didChangeWorkspaceFolders_notification, server)
        msg_dispatcher[workspace_symbol_request_type] = request_wrapper(workspace_symbol_request, server)
        msg_dispatcher[julia_refreshLanguageServer_notification_type] = notification_wrapper(julia_refreshLanguageServer_notification, server)
        msg_dispatcher[julia_getDocFromWord_request_type] = request_wrapper(julia_getDocFromWord_request, server)
        msg_dispatcher[textDocument_selectionRange_request_type] = request_wrapper(textDocument_selectionRange_request, server)
        msg_dispatcher[textDocument_documentLink_request_type] = request_wrapper(textDocument_documentLink_request, server)
        msg_dispatcher[textDocument_inlayHint_request_type] = request_wrapper(textDocument_inlayHint_request, server)
        msg_dispatcher[julia_get_test_env_request_type] = request_wrapper(julia_get_test_env_request, server)

        # The exit notification message should not be wrapped in request_wrapper (which checks
        # if the server have been requested to be shut down). Instead, this message needs to be
        # handled directly.
        msg_dispatcher[exit_notification_type] = (conn, params) -> exit_notification(params, server, conn)

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
                JSONRPC.dispatch_msg(server.jr_endpoint, msg_dispatcher, msg)
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
            end
        end
    end
end
