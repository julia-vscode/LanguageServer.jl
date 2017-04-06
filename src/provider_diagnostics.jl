function parse_diag(doc, server)
    ps = Parser.ParseState(doc._content)
    doc.blocks.ast, ps = Parser.parse(ps, true)
    diags = map(ps.hints) do h
        rng = Range(Position(get_position_at(doc, first(h.loc) + 1)..., one_based=true), Position(get_position_at(doc, last(h.loc) + 1)..., one_based=true))
        
        Diagnostic(rng, 2, string(typeof(h).parameters[1]), string(typeof(h).name), string(typeof(h).parameters[1]))
    end
    diags = unique(diags)
    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, diags)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), publishDiagnosticsParams)
    send(response, server)
    
end