function textDocument_hover_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)
    documentation = JuliaWorkspaces.get_hover_text(server.workspace, uri, index)
    return documentation === nothing ? nothing : Hover(MarkupContent(documentation), missing)
end

