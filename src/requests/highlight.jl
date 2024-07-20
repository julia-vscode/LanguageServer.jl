function textDocument_documentHighlight_request(params::DocumentHighlightParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    offset = get_offset(doc, params.position)
    identifier = get_identifier(getcst(doc), offset)
    identifier !== nothing || return nothing
    highlights = DocumentHighlight[]
    for_each_ref(identifier) do ref, doc1, o
        if get_uri(doc1) == get_uri(doc)
            kind = StaticLint.hasbinding(ref) ? DocumentHighlightKinds.Write : DocumentHighlightKinds.Read
            push!(highlights, DocumentHighlight(Range(doc, o .+ (0:ref.span)), kind))
        end
    end
    return isempty(highlights) ? nothing : highlights
end
