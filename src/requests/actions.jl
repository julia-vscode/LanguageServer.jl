struct ServerAction
    id::String
    desc::String
    kind::Union{CodeActionKind,Missing}
    preferred::Union{Bool,Missing}
    when::Function
    handler::Function
end

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
    jw_actions = JuliaWorkspaces.get_code_actions(server.workspace, uri, index, diag_messages)

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

    # AddLicenseIdentifier stays LS-only (depends on server.workspaceFolders)
    if haskey(LSActions, "AddLicenseIdentifier")
        sa = LSActions["AddLicenseIdentifier"]
        x = get_expr(jw_cst(server, uri), index)
        if x isa EXPR && sa.when(x, params, _empty_meta_dict)
            action = CodeAction(
                sa.desc,
                sa.kind,
                missing,
                client_preferred_support(server) ? sa.preferred : missing,
                missing,
                Command(sa.desc, sa.id, arguments),
            )
            push!(actions, action)
        end
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
    # AddLicenseIdentifier stays LS-only
    if params.command == "AddLicenseIdentifier" && haskey(LSActions, "AddLicenseIdentifier")
        uri = URI(params.arguments[1])
        offset = params.arguments[2]
        meta_dict, _ = get_meta_data(server, uri)
        x = get_expr(jw_cst(server, uri), offset)
        LSActions["AddLicenseIdentifier"].handler(x, server, conn, meta_dict)
        return
    end

    # All other actions delegate to JuliaWorkspaces
    uri = URI(params.arguments[1])
    index = params.arguments[2]  # already 1-based from codeAction handler

    file_edits = JuliaWorkspaces.execute_code_action(server.workspace, params.command, uri, index)
    isempty(file_edits) && return

    tdes = TextDocumentEdit[]
    for fe in file_edits
        edits = TextEdit[
            TextEdit(jw_range(server, fe.uri, te.start_offset:te.end_offset), te.new_text)
            for te in fe.edits
        ]
        push!(tdes, TextDocumentEdit(VersionedTextDocumentIdentifier(fe.uri, jw_version(server, fe.uri)), edits))
    end

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, tdes)))
end

function get_spdx_header(server::LanguageServerInstance, uri::URI)
    # note the multiline flag - without that, we'd try to match the end of the _document_
    # instead of the end of the line.
    m = match(r"(*ANYCRLF)^# SPDX-License-Identifier:\h+((?:[\w\.-]+)(?:\h+[\w\.-]+)*)\h*$"m, jw_text(server, uri))
    return m === nothing ? m : String(m[1])
end

function in_same_workspace_folder(server::LanguageServerInstance, file1::URI, file2::URI)
    file1_str = uri2filepath(file1)
    file2_str = uri2filepath(file2)
    (file1_str === nothing || file2_str === nothing) && return false
    for ws in server.workspaceFolders
        if startswith(file1_str, ws) &&
           startswith(file2_str, ws)
           return true
       end
    end
    return false
end

function identify_short_identifier(server::LanguageServerInstance, file_uri::URI)
    # First look in tracked files (in the same workspace folder) for existing headers
    candidate_identifiers = Set{String}()
    for uri in JuliaWorkspaces.get_text_files(server.workspace)
        in_same_workspace_folder(server, file_uri, uri) || continue
        id = get_spdx_header(server, uri)
        id === nothing || push!(candidate_identifiers, id)
    end
    if length(candidate_identifiers) == 1
        return first(candidate_identifiers)
    else
        numerous = iszero(length(candidate_identifiers)) ? "no" : "multiple"
        @warn "Found $numerous candidates for the SPDX header from open files, falling back to LICENSE" Candidates=candidate_identifiers
    end

    # Fallback to looking for a license file in the same workspace folder
    candidate_files = String[]
    for dir in server.workspaceFolders
        for f in joinpath.(dir, ["LICENSE", "LICENSE.md"])
            if in_same_workspace_folder(server, file_uri, filepath2uri(f)) && safe_isfile(f)
                push!(candidate_files, f)
            end
        end
    end

    num_candidates = length(candidate_files)
    if num_candidates != 1
        iszero(num_candidates) && @warn "No candidate for licenses found, can't add identifier!"
        num_candidates > 1 && @warn "More than one candidate for licenses found, choose licensing manually!"
        return nothing
    end

    # This is just a heuristic, but should be OK since this is not something automated, and
    # the programmer will see directly if the wrong license is added.
    license_text = read(first(candidate_files), String)

    # Some known different spellings of some licences
    if contains(license_text, r"^\s*MIT\s+(\"?Expat\"?\s+)?Licen[sc]e")
        return "MIT"
    elseif contains(license_text, r"^\s*EUROPEAN\s+UNION\s+PUBLIC\s+LICEN[CS]E\s+v\."i)
        # the first version should be the EUPL version
        version = match(r"\d\.\d", license_text).match
        return "EUPL-$version"
    end

    @warn "A license was found, but could not be identified! Consider adding its licence identifier once to a file manually so that LanguageServer.jl can find it automatically next time." Location=first(candidate_files)
    return nothing
end

function add_license_header(x, server::LanguageServerInstance, conn, meta_dict)
    loc = get_file_loc(x, server)
    loc === nothing && return
    uri, _ = loc
    # does the current file already have a header?
    get_spdx_header(server, uri) === nothing || return # TODO: Would be nice to check this already before offering the action
    # no, so try to find one
    short_identifier = identify_short_identifier(server, uri)
    short_identifier === nothing && return
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, 0:0), "# SPDX-License-Identifier: $(short_identifier)\n\n")
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end


# Adding a CodeAction requires defining:
# * a unique id
# * a description
# * an action kind (optionally)
# * a function (.when) called on the currently selected expression and parameters of the CodeAction call;
# * a function (.handler) called on three arguments (current expression, server and the jr connection) to implement the command.
const LSActions = Dict{String,ServerAction}()

LSActions["AddLicenseIdentifier"] = ServerAction(
    "AddLicenseIdentifier",
    "Add SPDX license identifier.",
    missing,
    missing,
    (_, params, meta_dict) -> params.range.start.line == 0,
    add_license_header,
)
