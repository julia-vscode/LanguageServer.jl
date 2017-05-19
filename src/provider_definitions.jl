function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character + 1)
    word = get_word(tdpp, server)
    y, s, modules, current_namespace = get_scope(doc, offset, server)

    locations = Location[]
    if y isa CSTParser.IDENTIFIER || y isa CSTParser.OPERATOR
        x = get_cache_entry(Expr(y), server, unique(modules))
    elseif y isa CSTParser.QUOTENODE && last(s.stack) isa CSTParser.EXPR && last(s.stack).head isa CSTParser.OPERATOR{16,Tokens.DOT}
        x = get_cache_entry(Expr(last(s.stack)), server, unique(modules))
    else
        x = nothing
    end
    for m in methods(x)
        file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
        push!(locations, Location(is_windows() ? "file:///$(URIParser.escape(replace(file, '\\', '/')))" : "file:$(file)", Range(m.line - 1, 0, m.line, 0)))
    end
    
    
    if y != nothing
        Ey = Expr(y)
        for (v, loc, uri) in s.symbols
            if Ey == v.id || (v.id isa Expr && v.id.head == :. && v.id.args[1] == current_namespace && Ey == v.id.args[2].value)
                doc1 = server.documents[uri]
                push!(locations, Location(uri, Range(doc1, loc)))
            end
        end
    end

    response = JSONRPC.Response(get(r.id), locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end
