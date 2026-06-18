function client_support_action_kind(s::LanguageServerInstance, _::CodeActionKind=CodeActionKinds.Empty)
    if s.clientCapabilities !== missing &&
       s.clientCapabilities.textDocument !== missing &&
       s.clientCapabilities.textDocument.codeAction !== missing &&
       s.clientCapabilities.textDocument.codeAction.codeActionLiteralSupport !== missing
       s.clientCapabilities.textDocument.codeAction.codeActionLiteralSupport.codeActionKind !== missing
        # From the spec of CodeActionKind (https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#codeActionClientCapabilities):
        #
        #     The code action kind values the client supports. When this
        #     property exists the client also guarantees that it will
        #     handle values outside its set gracefully and falls back
        #     to a default value when unknown.
        #
        # so we can always return true here(?).
        return true
    else
        return false
    end
end

function client_preferred_support(s::LanguageServerInstance)::Bool
    if s.clientCapabilities !== missing &&
       s.clientCapabilities.textDocument !== missing &&
       s.clientCapabilities.textDocument.codeAction !== missing &&
       s.clientCapabilities.textDocument.codeAction.isPreferredSupport !== missing
       return s.clientCapabilities.textDocument.codeAction.isPreferredSupport
   else
       return false
    end
end

# TODO: All currently supported CodeActions in LS.jl can be converted "losslessly" to
#       Commands but this might not be true in the future so unless the client support
#       literal code actions those need to be filtered out.
function convert_to_command(ca::CodeAction)
    return ca.command
end

function textDocument_codeAction_request(params::CodeActionParams, server::LanguageServerInstance, conn)
    actions = CodeAction[]
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.range.start)
    arguments = Any[params.textDocument.uri, index] # use the same arguments for all commands

    # Get code actions from JuliaWorkspaces
    diag_messages = String[d.message for d::Diagnostic in params.context.diagnostics]
    workspace_folders = [String(wf) for wf in server.workspaceFolders]
    jw_actions = JuliaWorkspaces.get_code_actions(server.workspace, uri, index, diag_messages, workspace_folders)

    for a in jw_actions
        kind = _jw_action_kind_to_lsp(a.kind)
        # VS Code workaround: SourceOrganizeImports doesn't show in the UI
        if kind !== missing && kind == CodeActionKinds.SourceOrganizeImports &&
            server.clientInfo !== missing && occursin("code", lowercase(server.clientInfo.name))
            kind = CodeActionKinds.RefactorRewrite
        end
        preferred = client_preferred_support(server) && a.is_preferred ? true : missing
        action = CodeAction(
            a.title,
            kind,
            missing,
            preferred,
            missing,
            Command(a.title, a.id, arguments),
        )
        push!(actions, action)
    end

    if client_support_action_kind(server)
        return actions
    else
        return convert_to_command.(actions)
    end
end

function _jw_action_kind_to_lsp(kind::Symbol)
    kind === :quickfix && return CodeActionKinds.QuickFix
    kind === :refactor && return CodeActionKinds.Refactor
    kind === :refactor_rewrite && return CodeActionKinds.RefactorRewrite
    kind === :source_organize_imports && return CodeActionKinds.SourceOrganizeImports
    return missing
end

function workspace_executeCommand_request(params::ExecuteCommandParams, server::LanguageServerInstance, conn)
    uri = URI(params.arguments[1])
    index = params.arguments[2]  # already 1-based from codeAction handler
    workspace_folders = [String(wf) for wf in server.workspaceFolders]

    file_edits = JuliaWorkspaces.execute_code_action(server.workspace, params.command, uri, index, workspace_folders)
    isempty(file_edits) && return

    tdes = TextDocumentEdit[]
    for fe in file_edits
        edits = TextEdit[
            TextEdit(jw_range(server, fe.uri, te.start, te.stop), te.new_text)
            for te in fe.edits
        ]
        push!(tdes, TextDocumentEdit(VersionedTextDocumentIdentifier(fe.uri, jw_version(server, fe.uri)), edits))
    end

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, tdes)))
end
