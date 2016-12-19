function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    word = get_word(tdpp, server)
    x = get_sym(word)

    locations = map(methods(x).ms) do m
        (filename, line) = functionloc(m)
        @static if is_windows()
            filename_norm = normpath(filename)
            filename_norm = replace(filename_norm, '\\', '/')
            filename_escaped = URIParser.escape(filename_norm)
            uri = "file:///$filename_escaped"
        else
            uri = "file:$filename"
        end
        return Location(uri, line-1)
    end

    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    ns = get_names(tdpp.textDocument.uri, server, offset)

    for v in keys(ns)
        if string(v)==word
            l0,c0 = get_position_at(doc, max(1, first(ns[v][3].typ)))
            l1,c1 = get_position_at(doc, last(ns[v][3].typ))
            push!(locations, Location(tdpp.textDocument.uri, Range(l0-1, c0-1, l1-1, c1-1)))
        end
    end

    response = JSONRPC.Response(get(r.id),locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end
