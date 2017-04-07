function parse_diag(doc, server)
    ps = Parser.ParseState(doc._content)
    doc.blocks.ast, ps = Parser.parse(ps, true)

    # Lint/Formatting hints
    diags = map(ps.hints) do h
        rng = Range(Position(get_position_at(doc, first(h.loc) + 1)..., one_based=true), Position(get_position_at(doc, last(h.loc) + 1)..., one_based=true))
        
        Diagnostic(rng, 2, string(typeof(h).parameters[1]), string(typeof(h).name), string(typeof(h).parameters[1]))
    end
    diags = unique(diags)

    # Errors
    if ps.errored
        ast = doc.blocks.ast
        if last(ast) isa Parser.ERROR
            if length(ast) > 1
                loc = sum(ast[i].span for i = 1:length(ast)-1):sizeof(doc._content)
            else
                loc = 0:sizeof(doc._content)
            end
            rng = Range(Position(get_position_at(doc, first(loc) + 1)..., one_based=true), Position(get_position_at(doc, last(loc) + 1)..., one_based=true))
            push!(diags, Diagnostic(rng, 1, "Parse failure", "Unknown", "Parse failure"))
        end
    end

    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, diags)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), publishDiagnosticsParams)
    send(response, server)
    
end