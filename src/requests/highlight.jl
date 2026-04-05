function textDocument_documentHighlight_request(params::DocumentHighlightParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    meta_dict, _ = get_meta_data(server, uri)
    offset = get_offset(st, params.position)
    identifier = get_identifier(jw_cst(server, uri), offset)
    identifier !== nothing || return nothing
    highlights = DocumentHighlight[]
    for_each_ref(identifier, meta_dict, server) do ref, ref_uri, o
        if ref_uri == uri
            kind = hasbinding(ref, meta_dict) ? DocumentHighlightKinds.Write : DocumentHighlightKinds.Read
            push!(highlights, DocumentHighlight(jw_range(server, ref_uri, o .+ (0:ref.span)), kind))
        end
    end
    return isempty(highlights) ? nothing : highlights
end
