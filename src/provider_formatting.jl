function process(r::JSONRPC.Request{Val{Symbol("textDocument/formatting")},DocumentFormattingParams}, server)
    if !haskey(server.documents, r.params.textDocument.uri)
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    doc = server.documents[r.params.textDocument.uri]
    edits = TextEdit[]

    F = DocumentFormat.FormatState(doc._content)
    ps = CSTParser.ParseState(doc._content)
    x, ps = CSTParser.parse(ps, true)
    DocumentFormat.format(x, F)
    lsedits = TextEdit[]
    edits = DocumentFormat.TextEdit[]
    for d in F.diagnostics
        append!(edits, d.edits)
    end
    sort!(edits, by = x -> -first(x.range))
    if !ps.errored
        for e in edits
            if length(e.range) == 0
                start_l, start_c = get_position_at(doc, first(e.range))
                push!(lsedits, TextEdit(Range(start_l - 1, start_c - 1, start_l - 1, start_c - 1), e.text))
            else
                start_l, start_c = get_position_at(doc, first(e.range))
                end_l, end_c = get_position_at(doc, last(e.range))
                push!(lsedits, TextEdit(Range(start_l - 1, start_c - 1, end_l - 1, end_c - 1), e.text))
            end
        end
        
    end
    

    response = JSONRPC.Response(get(r.id), lsedits)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/formatting")}}, params)
    return DocumentFormattingParams(params)
end
