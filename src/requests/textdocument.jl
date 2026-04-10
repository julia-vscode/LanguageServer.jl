function textDocument_didOpen_notification(params::DidOpenTextDocumentParams, server::LanguageServerInstance, conn)
    @debug "textDocument/didOpen" uri=params.textDocument.uri

    marked_versions = mark_current_diagnostics_testitems(server.workspace)

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
        JuliaWorkspaces.add_file!(server.workspace, new_text_file)
    end
    server._open_file_versions[uri] = params.textDocument.version

    publish_diagnostics_testitems(server, marked_versions, [uri])
end


function textDocument_didClose_notification(params::DidCloseTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri

    @debug "textDocument/didClose" uri=uri

    marked_versions = mark_current_diagnostics_testitems(server.workspace)

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

    publish_diagnostics_testitems(server, marked_versions, JuliaWorkspaces.URIs2.URI[])
end

function textDocument_didSave_notification(params::DidSaveTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    if params.text isa String
        if st.content != params.text
            println(stderr, "Mismatch between server and client text")
            println(stderr, "========== BEGIN SERVER SIDE TEXT ==========")
            println(stderr, st.content)
            println(stderr, "========== END SERVER SIDE TEXT ==========")
            println(stderr, "========== BEGIN CLIENT SIDE TEXT ==========")
            println(stderr, params.text)
            println(stderr, "========== END CLIENT SIDE TEXT ==========")
            JSONRPC.send(conn, window_showMessage_notification_type, ShowMessageParams(MessageTypes.Error, "Julia Extension: Please contact us! Your extension just crashed with a bug that we have been trying to replicate for a long time. You could help the development team a lot by contacting us at https://github.com/julia-vscode/julia-vscode so that we can work together to fix this issue."))
            throw(LSSyncMismatch("Mismatch between server and client text for $(uri). _open_in_editor is $(haskey(server._open_file_versions, uri)). _workspace_file is $(uri in server._workspace_files). _version is $(get(server._open_file_versions, uri, 0))."))
        end
    end
end

function textDocument_willSave_notification(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
end

function textDocument_willSaveWaitUntil_request(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
    return TextEdit[]
end

function measure_sub_operation(f, request_name, server)
    start_time = string(Dates.unix2datetime(time()), "Z")
    tic = time_ns()
    res = f()
    toc = time_ns()
    duration = (toc - tic) / 1e+6

    JSONRPC.send(
        server.jr_endpoint,
        telemetry_event_notification_type,
        Dict(
            "command" => "request_metric",
            "operationId" => string(uuid4()),
            "operationParentId" => g_operationId[],
            "name" => request_name,
            "duration" => duration,
            "time" => start_time
        )
    )

    return res
end

function textDocument_didChange_notification(params::DidChangeTextDocumentParams, server::LanguageServerInstance, conn)
    @debug "textDocument/didChange" uri=params.textDocument.uri change_count=length(params.contentChanges)

    marked_versions = mark_current_diagnostics_testitems(server.workspace)

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

    publish_diagnostics_testitems(server, marked_versions, [uri])
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
