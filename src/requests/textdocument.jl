function textDocument_didOpen_notification(params::DidOpenTextDocumentParams, server::LanguageServerInstance, conn)
    @debug "textDocument/didOpen" uri=params.textDocument.uri

    uri = params.textDocument.uri

    if !JuliaWorkspaces.has_file(server.workspace, uri)
        if any(i -> startswith(string(uri), string(filepath2uri(i))), server.workspaceFolders)
            push!(server._workspace_files, uri)
        end
    end

    if haskey(server._open_file_versions, uri)
        error("This should not happen")
    end

    new_text_file = JuliaWorkspaces.TextFile(uri, JuliaWorkspaces.SourceText(params.textDocument.text, params.textDocument.languageId))

    if haskey(server._files_from_disc, uri)
        JuliaWorkspaces.update_file!(server.workspace, new_text_file)
    else
        # `add_file!` handles promotion from indirect → regular automatically.
        JuliaWorkspaces.add_file!(server.workspace, new_text_file)
    end
    server._open_file_versions[uri] = params.textDocument.version

    publish_file_diagnostics_testitems(server, [uri])
    # Opening a file can promote it from indirect to regular; update the
    # watcher registrations right away rather than with the debounced sweep.
    reconcile_indirect_file_watchers(server)
    schedule_publish_sweep!(server)
end


function textDocument_didClose_notification(params::DidCloseTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri

    @debug "textDocument/didClose" uri=uri

    if !(uri in server._workspace_files)
        # Not a workspace file and being closed — will be removed from JW below
    end

    if !haskey(server._open_file_versions, uri)
        error("This should not happen")
    end
    delete!(server._open_file_versions, uri)

    # If the file exists on disc, we go back to that version
    if haskey(server._files_from_disc, uri)
        JuliaWorkspaces.update_file!(server.workspace, server._files_from_disc[uri])
    else
        JuliaWorkspaces.remove_file!(server.workspace, uri)
    end

    # Closing a file can demote it back to an indirect file; update the
    # watcher registrations right away rather than with the debounced sweep.
    reconcile_indirect_file_watchers(server)
    schedule_publish_sweep!(server)
end

function textDocument_didSave_notification(params::DidSaveTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    if params.text isa String && st.content != params.text
        # Only treat a save-time text mismatch as a fatal sync error when the
        # document is actually open in the editor and has received at least one
        # versioned update. Mismatches for closed/unversioned documents are
        # spurious (e.g. workspace files we track but the client never synced),
        # so we ignore them rather than crashing the server (see #1390).
        if haskey(server._open_file_versions, uri) && get(server._open_file_versions, uri, 0) > 0
            println(stderr, "Mismatch between server and client text")
            println(stderr, "========== BEGIN SERVER SIDE TEXT ==========")
            println(stderr, st.content)
            println(stderr, "========== END SERVER SIDE TEXT ==========")
            println(stderr, "========== BEGIN CLIENT SIDE TEXT ==========")
            println(stderr, params.text)
            println(stderr, "========== END CLIENT SIDE TEXT ==========")
            throw(LSSyncMismatch("Mismatch between server and client text for $(uri). _open_in_editor is $(haskey(server._open_file_versions, uri)). _workspace_file is $(uri in server._workspace_files). _version is $(get(server._open_file_versions, uri, 0))."))
        end
    end
end

function textDocument_willSave_notification(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
end

function textDocument_willSaveWaitUntil_request(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
    return TextEdit[]
end

function textDocument_didChange_notification(params::DidChangeTextDocumentParams, server::LanguageServerInstance, conn)
    @debug "textDocument/didChange" uri=params.textDocument.uri change_count=length(params.contentChanges)

    uri = params.textDocument.uri

    if !haskey(server._open_file_versions, uri)
        error("This should not happen")
    end

    if params.textDocument.version < server._open_file_versions[uri]
        error("The client and server have different textDocument versions for $(uri). LS version is $(server._open_file_versions[uri]), request version is $(params.textDocument.version).")
    end

    st = jw_source_text(server, uri)
    new_content = apply_text_edits(st, params.contentChanges)

    new_text_file = JuliaWorkspaces.TextFile(uri, JuliaWorkspaces.SourceText(new_content, st.language_id))
    JuliaWorkspaces.update_file!(server.workspace, new_text_file)

    server._open_file_versions[uri] = params.textDocument.version

    publish_file_diagnostics_testitems(server, [uri])
    schedule_publish_sweep!(server)
end

function textDocument_diagnostic_request(params::DocumentDiagnosticParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    jw_diags = (is_workspace_file(server, uri) && JuliaWorkspaces.has_file(server.workspace, uri)) ?
        JuliaWorkspaces.get_diagnostic(server.workspace, uri) : []
    result_id = string(hash(jw_diags))

    if !ismissing(params.previousResultId) && params.previousResultId == result_id
        return UnchangedDocumentDiagnosticReport("unchanged", result_id)
    end

    lsp_diags = build_lsp_diagnostics(server, uri, jw_diags)
    return FullDocumentDiagnosticReport("full", result_id, lsp_diags)
end

"""
is_diag_dependent_on_env(diag::Diagnostic)::Bool

Is this diagnostic reliant on the current environment being accurately represented?
"""
function is_diag_dependent_on_env(diag::Diagnostic)
    startswith(diag.message, "Missing reference: ") ||
    startswith(diag.message, "Possible method call error") ||
    startswith(diag.message, "An imported")
end
