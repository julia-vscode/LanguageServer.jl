# Pull-mode diagnostics run synchronously on the dispatch task and delay
# latency-critical requests (e.g. completion), so we use push mode instead.
const PULL_DIAGNOSTICS_ENABLED = false

# The languages whose documents we are willing to format. The formatter parses a
# whole document as Julia code, so it must only ever be offered for Julia source.
# Markdown (and Julia-markdown, which is Markdown with Julia chunks) is part of
# the client's document selector for every *other* feature, but formatting one of
# those as a single Julia file always fails — and, worse, registering as their
# formatting provider makes the editor pick us over the real Markdown formatter.
const FORMATTING_LANGUAGES = ["julia"]

formatting_document_selector() = DocumentSelector([DocumentFilter(l, missing, missing) for l in FORMATTING_LANGUAGES])

function client_supports_dynamic_registration(client::ClientCapabilities, capability::Symbol)
    ismissing(client.textDocument) && return false
    cap = getproperty(client.textDocument, capability)
    ismissing(cap) && return false
    return cap.dynamicRegistration === true
end

function ServerCapabilities(client::ClientCapabilities)
    prepareSupport = !ismissing(client.textDocument) && !ismissing(client.textDocument.rename) && client.textDocument.rename.prepareSupport === true

    client_supports_pull_diagnostics = !ismissing(client.textDocument) && !ismissing(client.textDocument.diagnostic)

    diagnostic_provider = PULL_DIAGNOSTICS_ENABLED && client_supports_pull_diagnostics ?
        DiagnosticOptions(missing, true, true) : missing

    # A static capability applies to the client's whole document selector, which
    # includes Markdown. When the client can handle dynamic registration we
    # advertise nothing here and register in `initialized_notification` instead,
    # scoped to `FORMATTING_LANGUAGES`. Clients without dynamic registration keep
    # the old, broader behaviour rather than losing formatting altogether.
    formatting_provider = client_supports_dynamic_registration(client, :formatting) ? missing : true
    range_formatting_provider = client_supports_dynamic_registration(client, :rangeFormatting) ? missing : true

    ServerCapabilities(
        TextDocumentSyncOptions(
            true,
            TextDocumentSyncKinds.Incremental,
            false,
            false,
            SaveOptions(true)
        ),
        CompletionOptions(false, [".", "@", "\"", "^"], missing),
        true,
        SignatureHelpOptions(["(", ","], missing),
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        missing,
        DocumentLinkOptions(false, missing),
        false,
        formatting_provider,
        range_formatting_provider,
        missing,
        RenameOptions(missing, prepareSupport),
        false,
        ExecuteCommandOptions(missing, collect(keys(JuliaWorkspaces._JW_ACTIONS))),
        true,
        true,
        true,
        WorkspaceOptions(WorkspaceFoldersOptions(true, true)),
        diagnostic_provider,
        missing
    )

end

hasreadperm(p::String) = (uperm(p) & 0x04) == 0x04

const MAX_WORKSPACE_JULIA_FILES = 5000

function load_rootpath(path)
    try
        return isdir(path) &&
            hasreadperm(path) &&
            path != "" &&
            path != homedir()
    catch err
        is_walkdir_error(err) || rethrow()
        return false
    end
end

# One walk per folder: reads all workspace files, tracks julia files in
# `server._workspace_files`, and returns the new files for the caller to
# `add_files!` in one batch.
function collect_folder_files!(server, path::String)
    files_to_add = JuliaWorkspaces.TextFile[]
    load_rootpath(path) || return files_to_add

    files = JuliaWorkspaces.read_path_into_textdocuments(filepath2uri(path); ignore_io_errors=true, file_limit=MAX_WORKSPACE_JULIA_FILES)
    if files === nothing
        @info "Your workspace folder has > $MAX_WORKSPACE_JULIA_FILES Julia files, server will not try to load them."
        return files_to_add
    end

    for tf in files
        # A subfolder of an already-watched folder yields duplicates; first
        # read wins.
        if !haskey(server._files_from_disc, tf.uri)
            server._files_from_disc[tf.uri] = tf
            if !haskey(server._open_file_versions, tf.uri)
                push!(files_to_add, tf)
            end
        end

        filepath = uri2filepath(tf.uri)
        if filepath !== nothing && isvalidjlfile(filepath)
            push!(server._workspace_files, tf.uri)
        end
    end

    return files_to_add
end

is_walkdir_error(_) = false
is_walkdir_error(::Base.IOError) = true
is_walkdir_error(::Base.SystemError) = true
@static if VERSION > v"1.3.0-"
    is_walkdir_error(err::Base.TaskFailedException) = is_walkdir_error(err.task.exception)
end

function initialize_request(params::InitializeParams, server::LanguageServerInstance, conn)
    # Only look at rootUri and rootPath if the client doesn't support workspaceFolders
    if !ismissing(params.capabilities.workspace) && (ismissing(params.capabilities.workspace.workspaceFolders) || params.capabilities.workspace.workspaceFolders == false)
        if !(params.rootUri isa Nothing)
            push!(server.workspaceFolders, uri2filepath(params.rootUri))
        elseif !(params.rootPath isa Nothing)
            push!(server.workspaceFolders,  params.rootPath)
        end
    elseif (params.workspaceFolders !== nothing) && (params.workspaceFolders !== missing)
        for wksp in params.workspaceFolders
            if wksp.uri !== nothing
                fpath = uri2filepath(wksp.uri)
                if fpath !== nothing
                    push!(server.workspaceFolders, fpath)
                end
            end
        end
    end

    server.clientCapabilities = params.capabilities
    server.clientInfo = params.clientInfo
    server.editor_pid = params.processId

    # Start watching the editor process now that its pid is known. (Previously
    # this ran in Base.run before initialize set editor_pid, so it was a no-op.)
    poll_editor_pid(server)

    if !ismissing(params.capabilities.window) && !ismissing(params.capabilities.window.workDoneProgress) && params.capabilities.window.workDoneProgress
        server.clientcapability_window_workdoneprogress = true
    else
        server.clientcapability_window_workdoneprogress = false
    end

    if !ismissing(params.capabilities.workspace) &&
        !ismissing(params.capabilities.workspace.didChangeConfiguration) &&
        !ismissing(params.capabilities.workspace.didChangeConfiguration.dynamicRegistration) &&
        params.capabilities.workspace.didChangeConfiguration.dynamicRegistration

        server.clientcapability_workspace_didChangeConfiguration = true
    end

    if !ismissing(params.initializationOptions) && params.initializationOptions !== nothing
        server.initialization_options = params.initializationOptions
    end

    if !ismissing(params.trace)
        server.trace_value[] = Int(parse_lsp_trace_value(params.trace))
    end

    return InitializeResult(ServerCapabilities(server.clientCapabilities), missing)
end


function initialized_notification(params::InitializedParams, server::LanguageServerInstance, conn)
    @debug "initialized_notification"

    server.status = :running

    client_capabilities_registrations = Registration[]

    if server.clientcapability_workspace_didChangeConfiguration
        push!(
            client_capabilities_registrations,
            Registration(string(uuid4()), "workspace/didChangeConfiguration", missing)
        )
    end

    # Register formatting only for Julia source. The static capability would apply
    # to the client's whole document selector, which also contains Markdown and
    # Julia-markdown; we cannot format those, and claiming we can stops the editor
    # from using the formatter that actually can (it picks a single provider per
    # document). `ServerCapabilities` leaves the static capability out whenever the
    # client advertises dynamic registration, so the two must stay in sync.
    if !ismissing(server.clientCapabilities)
        if client_supports_dynamic_registration(server.clientCapabilities, :formatting)
            push!(
                client_capabilities_registrations,
                Registration(
                    string(uuid4()),
                    "textDocument/formatting",
                    DocumentFormattingRegistrationOptions(formatting_document_selector(), missing)
                )
            )
        end

        if client_supports_dynamic_registration(server.clientCapabilities, :rangeFormatting)
            push!(
                client_capabilities_registrations,
                Registration(
                    string(uuid4()),
                    "textDocument/rangeFormatting",
                    DocumentRangeFormattingRegistrationOptions(formatting_document_selector(), missing)
                )
            )
        end
    end

    if !ismissing(server.clientCapabilities) &&
        !ismissing(server.clientCapabilities.workspace) &&
        !ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles) &&
        !ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles.dynamicRegistration) &&
        !ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles.relativePatternSupport) &&
        server.clientCapabilities.workspace.didChangeWatchedFiles.dynamicRegistration &&
        server.clientCapabilities.workspace.didChangeWatchedFiles.relativePatternSupport

        file_watchers = [
            FileSystemWatcher("**/*.{jl,jmd,md}", missing),
            FileSystemWatcher("**/{Project.toml,JuliaProject.toml,Manifest.toml,JuliaManifest.toml,JuliaLint.toml,JuliaFormat.toml,JuliaTestItems.toml}", missing),
            FileSystemWatcher("**/{JuliaManifest,Manifest}-v$(VERSION.major).$(VERSION.minor).toml", missing),
        ]

        if should_watch_directories(server)
            # VS Code (and the Code-OSS family) reports an atomic folder rename
            # or delete as a single event for the folder path, with no events
            # for the files inside, and no glob can match "directories only".
            # Watch everything for create/delete (the workspace watcher is
            # recursive anyway, so this only widens event delivery) and let the
            # notification handler sort out directories vs. relevant files; the
            # extension globs then only need to deliver content changes. Off by
            # default for other clients — most watcher backends synthesize
            # per-file events so the file globs suffice, and some (e.g.
            # Emacs-based ones) expand `**` into one OS watcher per directory —
            # but overridable via the `julialangDirectoryWatching`
            # initialization option (see `should_watch_directories`).
            file_watchers = [FileSystemWatcher(w.globPattern, WatchKinds.Change) for w in file_watchers]
            push!(file_watchers, FileSystemWatcher("**", WatchKinds.Create | WatchKinds.Delete))
        end

        push!(
            client_capabilities_registrations,
            Registration("workspace/didChangeWatchedFiles", "workspace/didChangeWatchedFiles", DidChangeWatchedFilesRegistrationOptions(file_watchers))
        )
    end

    if length(client_capabilities_registrations) > 0
        JSONRPC.send(
            conn,
            client_registerCapability_request_type,
            RegistrationParams(client_capabilities_registrations)
        )

    end

    # Record whether the client supports workspace/diagnostic/refresh. Only
    # relevant in pull mode; the flag also suppresses push-mode publishing.
    if PULL_DIAGNOSTICS_ENABLED &&
        !ismissing(server.clientCapabilities) &&
        !ismissing(server.clientCapabilities.workspace) &&
        !ismissing(server.clientCapabilities.workspace.diagnostics) &&
        !ismissing(server.clientCapabilities.workspace.diagnostics.refreshSupport) &&
        server.clientCapabilities.workspace.diagnostics.refreshSupport === true
        server.clientcapability_workspace_diagnostic_refreshsupport = true
    end

    # Fetch all initial configuration in one combined request, then construct JuliaWorkspace.
    # We do this inline (rather than via request_julia_config) because JW must be constructed
    # before we can call set_active_project! and load files. request_julia_config continues to
    # be called from workspace/didChangeConfiguration as before.
    if !ismissing(server.clientCapabilities) &&
        !ismissing(server.clientCapabilities.workspace) &&
        server.clientCapabilities.workspace.configuration === true

        # `julia.environmentPath` is deliberately not requested here: the client
        # resolves it (VS Code variables, `~`, relative paths) and passes the
        # absolute result as a launch arg (`server.env_path`), then pushes runtime
        # changes via the `julia/setEnvironmentPath` notification. Resolving the raw
        # setting here would duplicate that logic and can't handle `${env:...}` /
        # `${config:...}`, which only the client can expand.
        response = JSONRPC.send(conn, workspace_configuration_request_type, ConfigurationParams([
            ConfigurationItem(missing, "julia.completionmode"),
            ConfigurationItem(missing, "julia.inlayHints.static.enabled"),
            ConfigurationItem(missing, "julia.inlayHints.static.variableTypes.enabled"),
            ConfigurationItem(missing, "julia.inlayHints.static.parameterNames.enabled"),
            ConfigurationItem(missing, "julia.symbolCacheDownload"),
            ConfigurationItem(missing, "julia.symbolserverUpstream"),
            ConfigurationItem(missing, "julia.enableDynamicIndexing"),
            ConfigurationItem(missing, "julia.maxConcurrentIndexingProcesses"),
            ConfigurationItem(missing, "julia.enableWorkspaceEnvironmentResolution"),
        ]))

        server.completion_mode = Symbol(something(response[1], :import))
        server.inlay_hints = something(response[2], true)
        server.inlay_hints_variable_types = something(response[3], true)
        server.inlay_hints_parameter_names = Symbol(something(response[4], :literals))
        server.symbolcache_download = something(response[5], false)
        server.symbolcache_upstream = something(response[6], JuliaWorkspaces.DEFAULT_SYMBOLCACHE_UPSTREAM)
        server.enable_dynamic_indexing = something(response[7], true)
        server.max_concurrent_indexing_processes = something(response[8], 4)
        server.enable_workspace_environment_resolution = something(response[9], true)
    end

    # Construct JuliaWorkspace now that configuration values are available.
    indirect_cb = function(uri)
        put!(server.combined_msg_queue, (type=:indirect_file_discovered, uri=uri))
    end
    progress_cb = create_progress_callback(server)
    dynamic_mode = server.enable_dynamic_indexing ? JuliaWorkspaces.DynamicIndexingOnly : JuliaWorkspaces.DynamicOff
    server.workspace = JuliaWorkspace(;
        dynamic=dynamic_mode,
        store_path=server.symserver_store_path,
        symbolcache_download=server.symbolcache_download,
        symbolcache_upstream=server.symbolcache_upstream,
        indirect_file_watch_callback=indirect_cb,
        progress_callback=progress_cb,
        max_concurrent_djps=server.max_concurrent_indexing_processes,
        resolve_workspace_environments=server.enable_workspace_environment_resolution,
    )

    # A single "bootstrap" bar covers the synchronous load below, which is
    # otherwise silent (the first indexing bar only appears once add_files!
    # reconciles).
    progress_cb("bootstrap", "Scanning workspace files...", 0)

    TraceLogging.@trace "initial_workspace_load" begin
        if server.workspaceFolders !== nothing
            files_to_add = JuliaWorkspaces.TextFile[]
            TraceLogging.@trace "workspace folder walk" for folder in server.workspaceFolders
                append!(files_to_add, collect_folder_files!(server, folder))
            end

            progress_cb("bootstrap", "Loading $(length(files_to_add)) files...", 40)
            # Add the whole batch at once: this reconciles the required dynamic
            # processes a single time instead of once per file, so downloading/
            # indexing can start right after this call rather than after the
            # whole initial load.
            TraceLogging.@trace JuliaWorkspaces.add_files!(server.workspace, files_to_add)

            # `server.env_path` is the client-resolved absolute path from the
            # launch args (see `choose_env`); `filepath2uri` requires it to be
            # absolute, so guard rather than crash on anything unexpected.
            if isabspath(server.env_path) && ispath(server.env_path)
                TraceLogging.@trace JuliaWorkspaces.set_active_project!(server.workspace, filepath2uri(server.env_path))
            elseif !isempty(server.env_path)
                @warn "Ignoring `julia.environmentPath`: not an existing absolute path." env_path=server.env_path
            end
        end
    end

    # Test item discovery is purely static: it needs only the file text and the
    # `Project.toml` identity that `add_files!` just set as inputs, never any
    # DJP result. Publish it now so the Testing view fills in while indexing is
    # still running, instead of behind the full workspace lint below.
    progress_cb("bootstrap", "Discovering test items...", 60)
    TraceLogging.@trace run_testitem_publish_sweep(server)

    progress_cb("bootstrap", "Analyzing workspace...", 75)
    # The initial sweep touches the Salsa runtime (via get_diagnostics ->
    # process_from_dynamic -> set_input!). Only the dispatch loop may do that:
    # setting an input while a derived function is active is a hard error, so
    # this must run to completion here, not on a task that could interleave
    # with the next dispatched message. The sweep also records the published
    # baseline, so later indexing-complete refreshes publish only what changed.
    TraceLogging.@trace run_publish_sweep(server)
    progress_cb("bootstrap", "Workspace loaded", 100)

    return
end

function shutdown_request(params::Nothing, server::LanguageServerInstance, conn)
    server.shutdown_requested = true
    return nothing
end

function exit_notification(params::Nothing, server::LanguageServerInstance, conn)
    exit(server.shutdown_requested ? 0 : 1)
end
