function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    word = get_word(tdpp, server)
    
    locations = get_definitions(word, get_cache_entry(word, server, []))
    y, Y, I, O, scope = Parser.find_scope(doc.blocks.ast, offset)
    
    for (v, loc) in scope
        if word == string(v.id)
            rng = Range(Position(get_position_at(doc, first(loc))..., one_based=true), Position(get_position_at(doc, last(loc))..., one_based=true))
            push!(locations, Location(uri, rng))
        end
    end

    response = JSONRPC.Response(get(r.id),locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end


