function setTrace_notification(params::SetTraceParams, server::LanguageServerInstance, conn)
    server.trace_value[] = Int(parse_lsp_trace_value(params.value))
end

function julia_getCurrentBlockRange_request(tdpp::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    fallback = (Position(0, 0), Position(0, 0), tdpp.position)
    uri = tdpp.textDocument.uri

    JuliaWorkspaces.has_file(server.workspace, uri) || return nodocument_error(uri, "getCurrentBlockRange")

    st = jw_source_text(server, uri)

    if jw_version(server, uri) !== tdpp.version
        return mismatched_version_error(uri, jw_version(server, uri), tdpp, "getCurrentBlockRange")
    end

    index = index_at(st, tdpp.position)
    result = JuliaWorkspaces.get_current_block_range(server.workspace, uri, index)
    result === nothing && return fallback

    return (
        jw_position_to_lsp(server, uri, result.highlight_start),
        jw_position_to_lsp(server, uri, result.highlight_stop),
        jw_position_to_lsp(server, uri, result.block_stop)
    )
end

function textDocument_documentLink_request(params::DocumentLinkParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    results = JuliaWorkspaces.get_document_links(server.workspace, uri)

    return map(results) do r
        DocumentLink(jw_range(server, uri, r.start, r.stop), r.target_uri, missing, missing)
    end
end
