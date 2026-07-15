

function textDocument_definition_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    results = JuliaWorkspaces.get_definitions(server.workspace, uri, index)

    locations = map(results) do r
        Location(r.uri, jw_range(server, r.uri, r.start, r.stop))
    end

    return unique!(locations)
end

function textDocument_formatting_request(params::DocumentFormattingParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri

    file_edit = try
        JuliaWorkspaces.get_format_edits(server.workspace, uri)
    catch err
        return JSONRPC.JSONRPCError(
            -32000,
            "Failed to format document: $err.",
            nothing
        )
    end

    return TextEdit[
        TextEdit(jw_range(server, uri, te.start, te.stop), te.new_text)
        for te in file_edit.edits
    ]
end

function textDocument_range_formatting_request(params::DocumentRangeFormattingParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    start_line = params.range.start.line + 1
    stop_line = params.range.stop.line + 1

    file_edit = try
        JuliaWorkspaces.get_format_edits(server.workspace, uri, start_line, stop_line)
    catch err
        return JSONRPC.JSONRPCError(
            -33000,
            "Failed to format document: $err.",
            nothing
        )
    end

    return TextEdit[
        TextEdit(jw_range(server, uri, te.start, te.stop), te.new_text)
        for te in file_edit.edits
    ]
end

function textDocument_references_request(params::ReferenceParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    results = JuliaWorkspaces.get_references(server.workspace, uri, index)

    return map(results) do r
        Location(r.uri, jw_range(server, r.uri, r.start, r.stop))
    end
end

function textDocument_rename_request(params::RenameParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    edits = JuliaWorkspaces.get_rename_edits(server.workspace, uri, index, params.newName)
    isempty(edits) && return WorkspaceEdit(missing, TextDocumentEdit[])

    tdes = Dict{URI,TextDocumentEdit}()
    for e in edits
        if !haskey(tdes, e.uri)
            tdes[e.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(e.uri, jw_version(server, e.uri)), TextEdit[])
        end
        push!(tdes[e.uri].edits, TextEdit(jw_range(server, e.uri, e.start, e.stop), e.new_text))
    end

    return WorkspaceEdit(missing, collect(values(tdes)))
end

function textDocument_prepareRename_request(params::PrepareRenameParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    result = JuliaWorkspaces.can_rename(server.workspace, uri, index)
    result === nothing && return nothing

    return jw_range(server, uri, result.start, result.stop)
end

function textDocument_documentSymbol_request(params::DocumentSymbolParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    results = JuliaWorkspaces.get_document_symbols(server.workspace, uri)

    function convert_symbol(r::JuliaWorkspaces.DocumentSymbolResult)
        children = DocumentSymbol[convert_symbol(c) for c in r.children]
        rng = jw_range(server, uri, r.start, r.stop)
        DocumentSymbol(r.name, missing, r.kind, false, rng, rng, children)
    end

    return DocumentSymbol[convert_symbol(r) for r in results]
end

function julia_getModuleAt_request(params::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri

    if JuliaWorkspaces.has_file(server.workspace, uri)
        if jw_version(server, uri) == params.version
            st = jw_source_text(server, uri)
            index = index_at(st, params.position, true)
            result = JuliaWorkspaces.get_module_at(server.workspace, uri, index)
            return result === nothing ? "Main" : result
        else
            return mismatched_version_error(uri, jw_version(server, uri), params, "getModuleAt")
        end
    else
        return nodocument_error(uri, "getModuleAt")
    end
end

function julia_getDocAt_request(params::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    JuliaWorkspaces.has_file(server.workspace, uri) || return nodocument_error(uri, "getDocAt")

    st = jw_source_text(server, uri)
    if jw_version(server, uri) !== params.version
        return mismatched_version_error(uri, jw_version(server, uri), params, "getDocAt")
    end

    index = index_at(st, params.position)
    documentation = JuliaWorkspaces.get_hover_text(server.workspace, uri, index)

    return documentation === nothing ? "" : documentation
end

# TODO: handle documentation resolving properly, respect how Documenter handles that
function julia_getDocFromWord_request(params::NamedTuple{(:word,),Tuple{String}}, server::LanguageServerInstance, conn)
    return JuliaWorkspaces.get_doc_from_word(server.workspace, params.word)
end

function textDocument_selectionRange_request(params::SelectionRangeParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)

    indices = [index_at(st, p) for p in params.positions]
    results = JuliaWorkspaces.get_selection_ranges(server.workspace, uri, indices)

    function convert_selection(r::Union{Nothing, JuliaWorkspaces.SelectionRangeResult})
        r === nothing && return missing
        parent = convert_selection(r.parent)
        SelectionRange(jw_range(server, uri, r.start, r.stop), parent)
    end

    ret = SelectionRange[convert_selection(r) for r in results]
    return isempty(ret) ? nothing : ret
end

function textDocument_inlayHint_request(params::InlayHintParams, server::LanguageServerInstance, conn)::Union{Vector{InlayHint},Nothing}
    if !server.inlay_hints
        return nothing
    end

    uri = params.textDocument.uri
    st = jw_source_text(server, uri)

    # Clients can request hints for a range that extends past the current
    # document (e.g. a sync race between an edit and the request), so index in
    # forgiving mode to clamp out-of-range positions instead of crashing.
    start_index = index_at(st, params.range.start, true)
    end_index = index_at(st, params.range.stop, true)

    config = JuliaWorkspaces.InlayHintConfig(
        server.inlay_hints,
        server.inlay_hints_variable_types,
        server.inlay_hints_parameter_names
    )

    results = JuliaWorkspaces.get_inlay_hints(server.workspace, uri, start_index, end_index, config)
    isempty(results) && return nothing

    return map(results) do r
        kind = r.kind === :parameter ? InlayHintKinds.Parameter : InlayHintKinds.Type
        InlayHint(
            jw_position_to_lsp(server, uri, r.position),
            r.label,
            kind,
            missing,
            missing,
            r.padding_left,
            r.padding_right,
            missing
        )
    end
end
