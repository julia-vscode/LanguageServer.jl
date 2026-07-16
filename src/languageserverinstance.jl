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
    # A JSONRPC.JSONRPCEndpoint in production; `nothing` or any other object
    # with a `JSONRPC.send` method in tests (e.g. a recording endpoint).
    jr_endpoint::Any
    workspaceFolders::Set{String}

    env_path::String

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

    workspace::Union{JuliaWorkspace,Nothing}
    symserver_store_path::Union{Nothing,String}
    symbolcache_download::Bool
    symbolcache_upstream::String
    enable_dynamic_indexing::Bool

    clientcapability_workspace_diagnostic_refreshsupport::Bool

    # This has one entry for each open file (in the LSP sense). The key is the uri fo the file
    # and the value is the version of the file that the LS client sent.
    _open_file_versions::Dict{URI,Int}
    _files_from_disc::Dict{URI,JuliaWorkspaces.TextFile}
    # Tracks which files are workspace files (found on disc in a workspace folder).
    _workspace_files::Set{URI}


    # Indirect files: URIs requested by JW (via include traversal) for which we
    # have registered an LSP file watcher. Maps URI -> registration id so we can
    # unregister later. Reconciled in `reconcile_indirect_file_watchers`.
    _watched_indirect_files::Dict{URI,String}

    # Per-file hashes of the diagnostics/testitems the client last received.
    # The publish sweep diffs the current workspace state against these and
    # only publishes files whose state actually changed.
    _published_hashes::@NamedTuple{testitems::Dict{URI,UInt},diagnostics::Dict{URI,UInt}}
    # Debounce state for the workspace publish sweep (see
    # `schedule_publish_sweep!`). Only touched from the dispatch task; the
    # debounce timer communicates exclusively through `combined_msg_queue`.
    _sweep_pending::Bool
    _sweep_generation::Int
    _sweep_timer::Union{Nothing,Timer}
    _sweep_first_dirty_time::Float64

    trace_value::Threads.Atomic{Int}

    function LanguageServerInstance(@nospecialize(pipe_in), @nospecialize(pipe_out), env_path="", err_handler=nothing, symserver_store_path=nothing, julia_exe::Union{NamedTuple{(:path,:version),Tuple{String,VersionNumber}},Nothing}=nothing)
        endpoint = JSONRPC.JSONRPCEndpoint(pipe_in, pipe_out)

        combined_queue = Channel{Any}(Inf)

        server = new(
            endpoint,
            Set{String}(),
            env_path,
            :qualify, # options: :import or :qualify, anything else turns this off
            false,
            true,
            :literals,
            combined_queue,
            err_handler,
            :created,
            false,
            false,
            missing,
            missing,
            missing,
            nothing,
            false,
            nothing,
            symserver_store_path,
            false,
            "",
            true,
            false,
            Dict{URI,Int}(),
            Dict{URI,JuliaWorkspaces.TextFile}(),
            Set{URI}(),
            Dict{URI,String}(),
            (testitems=Dict{URI,UInt}(), diagnostics=Dict{URI,UInt}()),
            false,
            0,
            nothing,
            0.0,
            Threads.Atomic{Int}(Int(lsp_trace_off))
        )
        return server
    end
end

function Base.display(server::LanguageServerInstance)
    println(stderr, "Root: ", server.workspaceFolders)
    if server.workspace !== nothing
        for uri in JuliaWorkspaces.get_text_files(server.workspace)
            println(stderr, "  ", uri)
        end
    end
end

# Set to true to reload request handler functions with Revise (requires Revise loaded in Main)
const USE_REVISE = Ref(false)

# Thrown when a request/notification targets a document the server doesn't know
# about (e.g. a `vscode-notebook-cell:` URI we never received a didOpen for).
# Handlers fetch documents through jw_source_text, which raises this; the
# wrapper below turns it into a graceful JSON-RPC error instead of crashing.
struct MissingDocumentError <: Exception
    uri::URI
end

function invoke_handler(func, params, server::LanguageServerInstance, conn)
    try
        if USE_REVISE[] && isdefined(Main, :Revise)
            try
                Main.Revise.revise()
            catch e
                @warn "Reloading with Revise failed" exception = e
            end
            return Base.invokelatest(func, params, server, conn)
        else
            return func(params, server, conn)
        end
    catch err
        err isa MissingDocumentError || rethrow()
        @debug "Handler $(nameof(func)) targeted a document not in the server" uri = err.uri
        return JSONRPC.JSONRPCError(-32602, "Document not available: $(err.uri).", nothing)
    end
end

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
        invoke_handler(func, params, server, conn)
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
        invoke_handler(func, params, server, conn)
    end
end

# Convert a raw monotonic `time_ns()` value into an OpenTelemetry `HrTime` pair
# `[seconds, nanoseconds]`, where `seconds` is whole seconds since the Unix epoch and
# `nanoseconds` is the partial second in nanoseconds. `ref_unix`/`ref_ns` are a wall-clock
# (`time()`) and monotonic (`time_ns()`) pair captured at the same instant. The relative
# timing between events keeps full nanosecond resolution from the monotonic clock; only the
# absolute anchor is limited by the resolution of `time()`. Arithmetic on the nanosecond
# component is done in integers to avoid any floating-point precision loss.
function ns_to_hrtime(ns::UInt64, ref_unix::Float64, ref_ns::UInt64)
    ref_seconds = floor(Int64, ref_unix)
    ref_frac_ns = round(Int64, (ref_unix - ref_seconds) * 1e9)
    total_ns = ref_frac_ns + (signed(ns) - signed(ref_ns))
    seconds = ref_seconds + fld(total_ns, 1_000_000_000)
    partial_ns = mod(total_ns, 1_000_000_000)
    return (seconds, partial_ns)
end

# Trace receiver that forwards completed spans and correlated log records to the client as
# telemetry events. Established for the dynamic extent of each request dispatch via
# `TraceLogging.with_tracing`. `ref_unix`/`ref_ns` are the shared wall-clock/monotonic anchor
# used to convert the raw monotonic timestamps carried by spans and log records into `HrTime`.
struct LSPTraceReceiver{T} <: TraceLogging.AbstractTraceReceiver
    server::T
    ref_unix::Float64
    ref_ns::UInt64
end

# Completed trace spans (top-level requests and the derived-function computations they
# trigger) are sent to the client as `request_metric` telemetry.
function TraceLogging.receive_span(r::LSPTraceReceiver, span::TraceLogging.TraceSpan)
    endpoint = r.server.jr_endpoint
    endpoint === nothing && return nothing
    payload = Dict{String,Any}(
        "command" => "request_metric",
        "spanId" => TraceLogging.format_span_id(span.span_id),
        "parentSpanId" => span.parent_span_id === nothing ? nothing : TraceLogging.format_span_id(span.parent_span_id),
        "traceId" => TraceLogging.format_trace_id(span.trace_id),
        "name" => span.name,
        "time" => collect(ns_to_hrtime(span.start_time_ns, r.ref_unix, r.ref_ns)),
        "duration" => span.duration_ns
    )
    # Only attach attributes when the span actually carries some, to avoid allocating and
    # serializing an empty dict on every request.
    span.attributes === nothing || (payload["attributes"] = Dict{String,Any}(string(k) => v for (k, v) in pairs(span.attributes)))
    JSONRPC.send(endpoint, telemetry_event_notification_type, payload)
    return nothing
end

# Regular log records emitted while inside a trace scope are forwarded as `trace_log`
# telemetry, correlated with the enclosing span (parent) and the shared trace id (root).
function TraceLogging.receive_log(r::LSPTraceReceiver, log::NamedTuple)
    endpoint = r.server.jr_endpoint
    endpoint === nothing && return nothing
    payload = Dict{String,Any}(
        "command" => "trace_log",
        "spanId" => TraceLogging.format_span_id(TraceLogging._new_span_id()),
        "parentSpanId" => log.span_id === nothing ? nothing : TraceLogging.format_span_id(log.span_id),
        "traceId" => log.trace_id === nothing ? nothing : TraceLogging.format_trace_id(log.trace_id),
        "message" => string(log._module, ": ", log.message),
        "severity" => string(log.level),
        "time" => collect(ns_to_hrtime(log.time_ns, r.ref_unix, r.ref_ns))
    )
    isempty(log.kwargs) || (payload["attributes"] = Dict{String,Any}(string(k) => string(v) for (k, v) in log.kwargs))
    JSONRPC.send(endpoint, telemetry_event_notification_type, payload)
    return nothing
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

    # Reference pair used to convert the raw monotonic `time_ns()` timestamps carried by trace
    # spans and log records into wall-clock `HrTime` values for the client. Captured once here
    # so every event shares the same anchor.
    trace_time_reference_unix = time()
    trace_time_reference_ns = time_ns()

    # Receiver that turns completed spans and correlated log records into client telemetry. It
    # is established for the dynamic extent of each request dispatch (see below), so that
    # `trace`/`@trace` calls anywhere beneath a request — including Salsa
    # derived-function computations — are reported.
    trace_receiver = LSPTraceReceiver(server, trace_time_reference_unix, trace_time_reference_ns)

    new_logger = LoggingExtras.TeeLogger(
        # Enrich log records with the enclosing trace/span ids and forward them to the active
        # trace receiver (as `trace_log` telemetry) while still logging to the current logger.
        TraceLogging.TraceContextLogger(Logging.current_logger()),
        LSPTraceLogger(server),
    )

    Logging.with_logger(new_logger) do

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
        msg_dispatcher[julia_getDocFromWord_request_type] = request_wrapper(julia_getDocFromWord_request, server)
        msg_dispatcher[textDocument_selectionRange_request_type] = request_wrapper(textDocument_selectionRange_request, server)
        msg_dispatcher[textDocument_documentLink_request_type] = request_wrapper(textDocument_documentLink_request, server)
        msg_dispatcher[textDocument_inlayHint_request_type] = request_wrapper(textDocument_inlayHint_request, server)
        msg_dispatcher[julia_get_test_env_request_type] = request_wrapper(julia_get_test_env_request, server)
        msg_dispatcher[textDocument_diagnostic_request_type] = request_wrapper(textDocument_diagnostic_request, server)
        msg_dispatcher[workspace_diagnostic_request_type] = request_wrapper(workspace_diagnostic_request, server)

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
            elseif message.type == :indirect_file_discovered
                # Fired by JW's indirect_file_watch_callback from a Salsa
                # computation thread. Register a per-file LSP watcher so we
                # get notified when the file changes on disc.
                uri = message.uri
                if !haskey(server._watched_indirect_files, uri) && uri.scheme == "file"
                    path = JuliaWorkspaces.URIs2.uri2filepath(uri)
                    if path !== nothing
                        dir = dirname(path)
                        base = basename(path)
                        registration_id = string(uuid4())
                        registration = Registration(
                            registration_id,
                            "workspace/didChangeWatchedFiles",
                            DidChangeWatchedFilesRegistrationOptions([
                                FileSystemWatcher(
                                    RelativePattern(JuliaWorkspaces.URIs2.filepath2uri(dir), base),
                                    missing
                                )
                            ])
                        )
                        try
                            JSONRPC.send(
                                server.jr_endpoint,
                                client_registerCapability_request_type,
                                RegistrationParams([registration])
                            )
                            server._watched_indirect_files[uri] = registration_id
                        catch err
                            @error "Failed to register file watcher for indirect file" uri=uri exception=(err, catch_backtrace())
                        end
                    end
                end
            elseif message.type == :jw_indexing_complete
                if server.clientcapability_workspace_diagnostic_refreshsupport
                    JSONRPC.send(server.jr_endpoint, workspace_diagnosticRefresh_request_type, nothing)
                end
                # Indexing changes env-dependent lint results; publish the
                # difference (and testitem updates) right away.
                run_publish_sweep(server)
            elseif message.type == :publish_sweep
                handle_publish_sweep_msg!(server, message.generation)
            elseif message.type == :clientmsg
                msg = message.msg

                add_timer_message!(did_show_timer, timings, msg)

                # Wrap dispatch in a trace span named after the request method. The span (and
                # any nested derived-function spans) are delivered to the `LSPTraceReceiver` as
                # request metrics. The raw message parameters are attached as a span attribute
                # so they show up in the request telemetry. Tracing is only enabled (the
                # receiver only installed) when the client asked for request metrics; otherwise
                # dispatch runs with no tracing overhead.
                if LSPTraceValue(server.trace_value[]) == lsp_trace_verbose
                    TraceLogging.with_tracing(trace_receiver) do
                        TraceLogging.@trace msg.method (; params = msg.params) begin
                            JSONRPC.dispatch_msg(server.jr_endpoint, msg_dispatcher, msg)
                        end
                    end
                else
                    JSONRPC.dispatch_msg(server.jr_endpoint, msg_dispatcher, msg)
                end
            end
        end
    end
end
