function workspace_didChangeWatchedFiles_notification(params::DidChangeWatchedFilesParams, server::LanguageServerInstance, conn)
    marked_versions = mark_current_diagnostics_testitems(server.workspace)

    changed_uris = URI[]

    for change in params.changes
        uri = change.uri

        uri.scheme=="file" || continue

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

    publish_diagnostics_testitems(server, marked_versions, changed_uris)
end

function workspace_didChangeConfiguration_notification(params::DidChangeConfigurationParams, server::LanguageServerInstance, conn)
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

const LINT_DIABLED_DIRS = ["test", "docs"]

function request_julia_config(server::LanguageServerInstance, conn)
    (ismissing(server.clientCapabilities.workspace) || server.clientCapabilities.workspace.configuration !== true) && return

    response = JSONRPC.send(conn, workspace_configuration_request_type, ConfigurationParams([
        ConfigurationItem(missing, "julia.lint.call"), # LintOptions
        ConfigurationItem(missing, "julia.lint.iter"),
        ConfigurationItem(missing, "julia.lint.nothingcomp"),
        ConfigurationItem(missing, "julia.lint.constif"),
        ConfigurationItem(missing, "julia.lint.lazy"),
        ConfigurationItem(missing, "julia.lint.datadecl"),
        ConfigurationItem(missing, "julia.lint.typeparam"),
        ConfigurationItem(missing, "julia.lint.modname"),
        ConfigurationItem(missing, "julia.lint.pirates"),
        ConfigurationItem(missing, "julia.lint.useoffuncargs"),
        ConfigurationItem(missing, "julia.lint.run"),
        ConfigurationItem(missing, "julia.lint.missingrefs"),
        ConfigurationItem(missing, "julia.lint.disabledDirs"),
        ConfigurationItem(missing, "julia.completionmode"),
        ConfigurationItem(missing, "julia.inlayHints.static.enabled"),
        ConfigurationItem(missing, "julia.inlayHints.static.variableTypes.enabled"),
        ConfigurationItem(missing, "julia.inlayHints.static.parameterNames.enabled"),
    ]))

    new_runlinter = something(response[11], true)
    new_SL_opts = StaticLint.LintOptions(response[1:10]...)

    new_lint_missingrefs = Symbol(something(response[12], :all))
    new_lint_disableddirs = something(response[13], LINT_DIABLED_DIRS)
    new_completion_mode = Symbol(something(response[14], :import))
    inlayHints = something(response[15], true)
    inlayHintsVariableTypes = something(response[16], true)
    inlayHintsParameterNames = Symbol(something(response[17], :literals))

    rerun_lint = begin
        any(getproperty(server.lint_options, opt) != getproperty(new_SL_opts, opt) for opt in fieldnames(StaticLint.LintOptions)) ||
        server.runlinter != new_runlinter ||
        server.lint_missingrefs != new_lint_missingrefs ||
        server.lint_disableddirs != new_lint_disableddirs
    end

    server.lint_options = new_SL_opts
    server.runlinter = new_runlinter
    server.lint_missingrefs = new_lint_missingrefs
    server.lint_disableddirs = new_lint_disableddirs
    server.completion_mode = new_completion_mode
    server.inlay_hints = inlayHints
    server.inlay_hints_variable_types = inlayHintsVariableTypes
    server.inlay_hints_parameter_names = inlayHintsParameterNames
end

function gc_files_from_workspace(server::LanguageServerInstance)
    for uri in keys(server._files_from_disc)
        if any(i->startswith(string(uri), i), string.(filepath2uri.(server.workspaceFolders)))
            continue
        end

        if uri in server._extra_tracked_files
            continue
        end

        delete!(server._files_from_disc, uri)

        if !haskey(server._open_file_versions, uri)
            JuliaWorkspaces.remove_file!(server.workspace, uri)
        end
    end
end

function workspace_didChangeWorkspaceFolders_notification(params::DidChangeWorkspaceFoldersParams, server::LanguageServerInstance, conn)
    marked_versions = mark_current_diagnostics_testitems(server.workspace)

    added_uris = URI[]

    for wksp in params.event.added
        push!(server.workspaceFolders, uri2filepath(wksp.uri))
        load_folder(wksp, server, added_uris)


        files = JuliaWorkspaces.read_path_into_textdocuments(wksp.uri, ignore_io_errors=true)

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

    for wksp in params.event.removed
        delete!(server.workspaceFolders, uri2filepath(wksp.uri))
        remove_workspace_files(wksp, server)

        gc_files_from_workspace(server)
    end

    publish_diagnostics_testitems(server, marked_versions, added_uris)
end

function workspace_symbol_request(params::WorkspaceSymbolParams, server::LanguageServerInstance, conn)
    results = JuliaWorkspaces.get_workspace_symbols(server.workspace, params.query)

    return map(results) do r
        SymbolInformation(r.name, r.kind, false, Location(r.uri, jw_range(server, r.uri, r.start_offset:r.end_offset)), missing)
    end
end
