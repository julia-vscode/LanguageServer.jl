function textDocument_documentHighlight_request(params::DocumentHighlightParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    results = JuliaWorkspaces.get_highlights(server.workspace, uri, index)
    isempty(results) && return nothing

    return map(results) do r
        kind = r.kind === :write ? DocumentHighlightKinds.Write : DocumentHighlightKinds.Read
        DocumentHighlight(jw_range(server, uri, r.start, r.stop), kind)
    end
end
