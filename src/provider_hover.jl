function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)

    y, Y, I, O, scope, modules = get_scope(doc, offset, server)

    if y isa Parser.IDENTIFIER || y isa Parser.OPERATOR
        entry = get_cache_entry(string(Expr(y)), server, modules)
        documentation = entry[1] != :EMPTY ? Any[entry[2]] : []
        for (v, loc, uri) in scope
            if Expr(y) == v.id
                push!(documentation, MarkedString(string(Expr(v.val))))
            end
        end
    elseif y isa Parser.QUOTENODE && last(Y) isa Parser.EXPR && last(Y).head isa Parser.OPERATOR{15, Tokens.DOT}
        if Expr(last(Y)[1]) in keys(server.cache) && Expr(y).value in keys(server.cache[Expr(last(Y)[1])]) && !(server.cache[Expr(last(Y)[1])][Expr(y).value] isa Dict)
            documentation = [server.cache[Expr(last(Y)[1])][Expr(y).value][2]]
        else
            documentation = [""]
        end
    elseif y isa Parser.LITERAL
        documentation = [string(lowercase(string(typeof(y).parameters[1])), ":"), MarkedString(string(Expr(y)))]
    else
        documentation = [string(Expr(y))]
    end
    response = JSONRPC.Response(get(r.id), Hover(documentation))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end
