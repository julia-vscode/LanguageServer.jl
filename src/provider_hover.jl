function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character)

    y, Y, I, O, scope = Parser.find_scope(doc.blocks.ast, offset)

    if y isa Parser.IDENTIFIER
        entry = get_cache_entry(string(y.val), server, [])
        documentation = entry[1] != :EMPTY ? Any[entry[2]] : []
        if !isempty(scope)
            for (v, loc) in scope
                if y.val == v.id
                    push!(documentation, MarkedString(string(Expr(v.val))))
                end
            end
        end
    elseif y isa Parser.OPERATOR
        entry = get_cache_entry(string(Expr(y)), server, [])
        documentation = entry[1] != :EMPTY ? [entry[2]] : []
    elseif y isa Parser.LITERAL
        documentation = [string(lowercase(string(typeof(y).parameters[1])),":"),MarkedString(string(Expr(y)))]
    else
        documentation = [string(Expr(y))]
    end
    response = JSONRPC.Response(get(r.id), Hover(documentation))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end
