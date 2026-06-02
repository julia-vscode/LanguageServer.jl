function ServerCapabilities(client::ClientCapabilities)
    prepareSupport = !ismissing(client.textDocument) && !ismissing(client.textDocument.rename) && client.textDocument.rename.prepareSupport === true

    client_supports_pull_diagnostics = !ismissing(client.textDocument) && !ismissing(client.textDocument.diagnostic)

    diagnostic_provider = client_supports_pull_diagnostics ?
        DiagnosticOptions(missing, true, true) : missing

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
        true,
        true,
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

function isjuliabasedir(path)
    try
        fs = readdir(path)
        if "base" in fs && isdir(joinpath(path, "base"))
            return isjuliabasedir(joinpath(path, "base"))
        end
        return all(f -> f in fs, ["coreimg.jl", "coreio.jl", "inference.jl"])
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return false
    end
end

function has_too_many_files(path, N=5000)
    i = 0

    try
        for (_, _, files) in walkdir(path, onerror=x -> x)
            for file in files
                if endswith(file, ".jl")
                    i += 1
                end
                if i > N
                    @info "Your workspace folder has > $N Julia files, server will not try to load them."
                    return true
                end
            end
        end
    catch err
        is_walkdir_error(err) || rethrow()
        return false
    end

    return false
end

function load_rootpath(path)
    try
        return isdir(path) &&
            hasreadperm(path) &&
            path != "" &&
            path != homedir() &&
            !isjuliabasedir(path) &&
            !has_too_many_files(path)
    catch err
        is_walkdir_error(err) || rethrow()
        return false
    end
end

function load_folder(wf::WorkspaceFolder, server, added_uris)
    path = uri2filepath(wf.uri)
    load_folder(path, server, added_uris)
end

function load_folder(path::String, server, added_uris)
    if load_rootpath(path)
        try
            for (root, _, files) in walkdir(path, onerror=x -> x)
                for file in files
                    filepath = joinpath(root, file)
                    if isvalidjlfile(filepath)
                        uri = filepath2uri(filepath)
                        already_tracked = uri in server._workspace_files
                        push!(server._workspace_files, uri)
                        if !already_tracked && JuliaWorkspaces.has_file(server.workspace, uri)
                            push!(added_uris, uri)
                        end
                    end
                end
            end
        catch err
            is_walkdir_error(err) || rethrow()
        end
    end
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

    if !ismissing(server.clientCapabilities) &&
        !ismissing(server.clientCapabilities.workspace) &&
        !ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles) &&
        !ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles.dynamicRegistration) &&
        !ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles.relativePatternSupport) &&
        server.clientCapabilities.workspace.didChangeWatchedFiles.dynamicRegistration &&
        server.clientCapabilities.workspace.didChangeWatchedFiles.relativePatternSupport

        push!(
            client_capabilities_registrations,
            Registration("workspace/didChangeWatchedFiles", "workspace/didChangeWatchedFiles", DidChangeWatchedFilesRegistrationOptions([
                FileSystemWatcher("**/*.{jl,jmd,md}", missing),
                FileSystemWatcher("**/{Project.toml,JuliaProject.toml,Manifest.toml,JuliaManifest.toml,JuliaLint.toml,JuliaFormat.toml}", missing),
                FileSystemWatcher("**/{JuliaManifest,Manifest}-v$(VERSION.major).$(VERSION.minor).toml", missing),
            ]))
        )
    end

    if length(client_capabilities_registrations) > 0
        JSONRPC.send(
            conn,
            client_registerCapability_request_type,
            RegistrationParams(client_capabilities_registrations)
        )

    end

    # Record whether the client supports workspace/diagnostic/refresh
    if !ismissing(server.clientCapabilities) &&
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

        response = JSONRPC.send(conn, workspace_configuration_request_type, ConfigurationParams([
            ConfigurationItem(missing, "julia.completionmode"),
            ConfigurationItem(missing, "julia.inlayHints.static.enabled"),
            ConfigurationItem(missing, "julia.inlayHints.static.variableTypes.enabled"),
            ConfigurationItem(missing, "julia.inlayHints.static.parameterNames.enabled"),
            ConfigurationItem(missing, "julia.environmentPath"),
            ConfigurationItem(missing, "julia.symbolCacheDownload"),
            ConfigurationItem(missing, "julia.symbolserverUpstream"),
            ConfigurationItem(missing, "julia.enableDynamicIndexing"),
        ]))

        server.completion_mode = Symbol(something(response[1], :import))
        server.inlay_hints = something(response[2], true)
        server.inlay_hints_variable_types = something(response[3], true)
        server.inlay_hints_parameter_names = Symbol(something(response[4], :literals))
        new_env_path = something(response[5], "")
        if !isempty(new_env_path)
            server.env_path = new_env_path
        end
        server.symbolcache_download = something(response[6], false)
        server.symbolcache_upstream = something(response[7], JuliaWorkspaces.DEFAULT_SYMBOLCACHE_UPSTREAM)
        server.enable_dynamic_indexing = something(response[8], true)
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
        progress_callback=progress_cb
    )

    marked_versions = mark_current_diagnostics_testitems(server.workspace)
    added_uris = URI[]

    if server.workspaceFolders !== nothing
        for i in server.workspaceFolders
            files = JuliaWorkspaces.read_path_into_textdocuments(filepath2uri(i), ignore_io_errors=true)

            for i in files
                # This might be a sub folder of a folder that is already watched
                # so we make sure we don't have duplicates
                if !haskey(server._files_from_disc, i.uri)
                    server._files_from_disc[i.uri] = i

                    if !haskey(server._open_file_versions, i.uri)
                        JuliaWorkspaces.add_file!(server.workspace, i)
                    end
                end
            end
        end

        JuliaWorkspaces.set_active_project!(server.workspace, isempty(server.env_path) ? nothing : filepath2uri(server.env_path))

        for wkspc in server.workspaceFolders
            load_folder(wkspc, server, added_uris)
        end
    end

    publish_diagnostics_testitems(server, marked_versions, added_uris)
end

function shutdown_request(params::Nothing, server::LanguageServerInstance, conn)
    server.shutdown_requested = true
    return nothing
end

function exit_notification(params::Nothing, server::LanguageServerInstance, conn)
    exit(server.shutdown_requested ? 0 : 1)
end
