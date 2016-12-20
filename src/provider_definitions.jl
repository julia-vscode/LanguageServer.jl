function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    ns = get_names(tdpp.textDocument.uri, offset, server)
    word = get_word(tdpp, server)
    
    modules = ns[:loaded_modules]
    locations = get_cache_entry(word, server, modules)[4]

    for v in keys(ns)
        if string(v)==word
            scope, t, def, uri = ns[v]
            l0,c0 = get_position_at(server.documents[uri], max(1, first(def.typ)))
            l1,c1 = get_position_at(server.documents[uri], last(def.typ))
            push!(locations, Location(uri, Range(l0-1, c0, l1-1, c1)))
            if t==:DataType
                for constructor in ns[v][5]
                    l0,c0 = get_position_at(server.documents[constructor[2]], max(1, first(constructor[1].typ)))
                    l1,c1 = get_position_at(server.documents[constructor[2]], last(constructor[1].typ))
                    push!(locations, Location(constructor[2], Range(l0-1, c0, l1-1, c1)))
                end
            end
        end
    end

    response = JSONRPC.Response(get(r.id),locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end
