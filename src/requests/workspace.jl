function workspace_didChangeWatchedFiles_notification(params::DidChangeWatchedFilesParams, server::LanguageServerInstance, conn)
    @debug "workspace/didChangeWatchedFiles" change_count=length(params.changes)

    changed_uris = URI[]

    for change in params.changes
        uri = change.uri

        uri.scheme=="file" || continue

        # If this URI is currently tracked as an indirect file, route updates
        # to JW's indirect-file API instead of the regular file path. The
        # indirect file does not appear in `_files_from_disc` / `_workspace_files`.
        if haskey(server._watched_indirect_files, uri) && !JuliaWorkspaces.has_file(server.workspace, uri)
            if change.type == FileChangeTypes.Created || change.type == FileChangeTypes.Changed
                text_file = JuliaWorkspaces.read_text_file_from_uri(uri, return_nothing_on_io_error=true)
                JuliaWorkspaces.set_indirect_file_content!(server.workspace, uri, text_file)
            elseif change.type == FileChangeTypes.Deleted
                JuliaWorkspaces.set_indirect_file_content!(server.workspace, uri, nothing)
            end
            continue
        end

        if change.type == FileChangeTypes.Created || change.type == FileChangeTypes.Changed
            text_file = JuliaWorkspaces.read_text_file_from_uri(uri, return_nothing_on_io_error=true)

            # First handle case where file could not be found or has invalid content
            if text_file === nothing
                if haskey(server._files_from_disc, uri)
                    delete!(server._files_from_disc, uri)
                end

                if !haskey(server._open_file_versions, uri) && JuliaWorkspaces.has_file(server.workspace, uri)
                    JuliaWorkspaces.remove_file!(server.workspace, uri)
                end
            else
                server._files_from_disc[uri] = text_file

                if !haskey(server._open_file_versions, uri)
                    if JuliaWorkspaces.has_file(server.workspace, uri)
                        JuliaWorkspaces.update_file!(server.workspace, text_file)
                    else
                        JuliaWorkspaces.add_file!(server.workspace, text_file)
                    end

                    push!(server._workspace_files, uri)
                    push!(changed_uris, uri)
                end
            end
        elseif change.type == FileChangeTypes.Deleted
            delete!(server._files_from_disc, uri)
            if !haskey(server._open_file_versions, uri) && JuliaWorkspaces.has_file(server.workspace, uri)
                JuliaWorkspaces.remove_file!(server.workspace, uri)
            end

            if !haskey(server._open_file_versions, uri)
                delete!(server._workspace_files, uri)
            end
        else
            error("Unknown change type.")
        end
    end

    publish_file_diagnostics_testitems(server, changed_uris)
    schedule_publish_sweep!(server)
end

function workspace_didChangeConfiguration_notification(params::DidChangeConfigurationParams, server::LanguageServerInstance, conn)
    @debug "workspace/didChangeConfiguration"

    if !server.clientcapability_workspace_didChangeConfiguration
        @debug "Client sent a `workspace/didChangeConfiguration` request despite claiming no support for it. " *
               "The request will be handled regardless, but this behavior can be reported to the client."
    end
    request_julia_config(server, conn)
end

@static if VERSION < v"1.1"
    isnothing(::Any) = false
    isnothing(::Nothing) = true
end

# Resolve a configured `julia.environmentPath` to an absolute, existing path, or
# return `nothing` if it can't be used. `filepath2uri` errors on relative paths,
# so a relative value is only accepted when there is exactly one workspace folder
# to resolve it against (with more than one the base is ambiguous); resolving
# against the server's cwd would silently point at the wrong project. The empty
# string (setting cleared) is handled by the caller, not here.
function resolve_env_path(server::LanguageServerInstance, path::AbstractString)
    isempty(path) && return nothing
    if !isabspath(path) && length(server.workspaceFolders) == 1
        path = joinpath(first(server.workspaceFolders), path)
    end
    return (isabspath(path) && ispath(path)) ? path : nothing
end

function request_julia_config(server::LanguageServerInstance, conn)
    (ismissing(server.clientCapabilities.workspace) || server.clientCapabilities.workspace.configuration !== true) && return

    response = JSONRPC.send(conn, workspace_configuration_request_type, ConfigurationParams([
        ConfigurationItem(missing, "julia.completionmode"),
        ConfigurationItem(missing, "julia.inlayHints.static.enabled"),
        ConfigurationItem(missing, "julia.inlayHints.static.variableTypes.enabled"),
        ConfigurationItem(missing, "julia.inlayHints.static.parameterNames.enabled"),
        ConfigurationItem(missing, "julia.environmentPath"),
        ConfigurationItem(missing, "julia.symbolCacheDownload"),
        ConfigurationItem(missing, "julia.symbolserverUpstream"),
        ConfigurationItem(missing, "julia.enableDynamicIndexing"),
        ConfigurationItem(missing, "julia.maxConcurrentIndexingProcesses"),
        ConfigurationItem(missing, "julia.enableWorkspaceEnvironmentResolution"),
    ]))

    new_completion_mode = Symbol(something(response[1], :import))
    inlayHints = something(response[2], true)
    inlayHintsVariableTypes = something(response[3], true)
    inlayHintsParameterNames = Symbol(something(response[4], :literals))

    server.completion_mode = new_completion_mode
    server.inlay_hints = inlayHints
    server.inlay_hints_variable_types = inlayHintsVariableTypes
    server.inlay_hints_parameter_names = inlayHintsParameterNames

    new_env_path = something(response[5], "")
    if server.env_path != new_env_path
        if isempty(new_env_path)
            # The user cleared the setting: drop the active project.
            server.env_path = new_env_path
            JuliaWorkspaces.set_active_project!(server.workspace, nothing)
        else
            resolved = resolve_env_path(server, new_env_path)
            if resolved !== nothing
                server.env_path = new_env_path
                JuliaWorkspaces.set_active_project!(server.workspace, filepath2uri(resolved))
            else
                # Not an existing absolute path, and not resolvable against a
                # single workspace folder; ignore it and keep the current project.
                @warn "Ignoring `julia.environmentPath`: not usable as an active project." new_env_path
            end
        end
    end

    # Store new settings on server; JW is not reconfigured at runtime (future work).
    server.symbolcache_download = something(response[6], false)
    server.symbolcache_upstream = something(response[7], JuliaWorkspaces.DEFAULT_SYMBOLCACHE_UPSTREAM)
    server.enable_dynamic_indexing = something(response[8], true)
    server.max_concurrent_indexing_processes = something(response[9], 4)
    server.enable_workspace_environment_resolution = something(response[10], true)
end

function gc_files_from_workspace(server::LanguageServerInstance)
    for uri in keys(server._files_from_disc)
        if any(i->startswith(string(uri), i), string.(filepath2uri.(server.workspaceFolders)))
            continue
        end

        delete!(server._files_from_disc, uri)

        if !haskey(server._open_file_versions, uri)
            JuliaWorkspaces.remove_file!(server.workspace, uri)
        end
    end
end

function workspace_didChangeWorkspaceFolders_notification(params::DidChangeWorkspaceFoldersParams, server::LanguageServerInstance, conn)
    @debug "workspace/didChangeWorkspaceFolders" added=length(params.event.added) removed=length(params.event.removed)

    for wksp in params.event.added
        path = uri2filepath(wksp.uri)
        push!(server.workspaceFolders, path)
        files_to_add = collect_folder_files!(server, path)
        JuliaWorkspaces.add_files!(server.workspace, files_to_add)
    end

    for wksp in params.event.removed
        delete!(server.workspaceFolders, uri2filepath(wksp.uri))
        remove_workspace_files(wksp, server)

        gc_files_from_workspace(server)
    end

    # Folder addition/removal is a bulk change; publish the new state right
    # away instead of debouncing.
    run_publish_sweep(server)
end

function workspace_symbol_request(params::WorkspaceSymbolParams, server::LanguageServerInstance, conn)
    results = JuliaWorkspaces.get_workspace_symbols(server.workspace, params.query)

    return map(results) do r
        SymbolInformation(r.name, r.kind, false, Location(r.uri, jw_range(server, r.uri, r.start, r.stop)), missing)
    end
end

function workspace_diagnostic_request(params::WorkspaceDiagnosticParams, server::LanguageServerInstance, conn)
    previous_result_ids = Dict{String,String}()
    for pr in params.previousResultIds
        previous_result_ids[string(pr.uri)] = pr.value
    end

    items = Union{WorkspaceFullDocumentDiagnosticReport,WorkspaceUnchangedDocumentDiagnosticReport}[]

    for (uri, _) in JuliaWorkspaces.get_diagnostics(server.workspace)
        is_workspace_file(server, uri) || continue
        diags = JuliaWorkspaces.get_diagnostic(server.workspace, uri)
        result_id = string(hash(diags))
        version = get(server._open_file_versions, uri, missing)

        if get(previous_result_ids, string(uri), nothing) == result_id
            push!(items, WorkspaceUnchangedDocumentDiagnosticReport(uri, version, "unchanged", result_id))
        else
            lsp_diags = build_lsp_diagnostics(server, uri, diags)
            push!(items, WorkspaceFullDocumentDiagnosticReport(uri, version, "full", result_id, lsp_diags))
        end
    end

    return WorkspaceDiagnosticReport(items)
end
