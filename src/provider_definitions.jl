function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    ns = get_names(tdpp.textDocument.uri, offset, server)
    word = get_word(tdpp, server)
    
    locations = get_definitions(word, get_cache_entry(word, server, ns.modules))
    
    for k in keys(ns.list)
        if string(k)==word
            v = ns.list[k]
            if isa(v, LocalVar)
                cloc =code_loc(v.def)
                cloc == 0:0 && break
                range = Range(Position(get_position_at(doc, max(1, first(cloc)))..., one_based=true), Position(get_position_at(doc, last(cloc))..., one_based=true))
                push!(locations, Location(v.uri, range))
                for m in v.methods
                    doc1 = server.documents[m[2]]
                    cloc1 = code_loc(m[1].typ)
                    cloc1==0:0 && continue
                    range = Range(Position(get_position_at(doc1, first(cloc1))..., one_based=true), Position(get_position_at(doc1, last(cloc1))..., one_based=true))
                    push!(locations, Location(m[2], range))
                end
            else
                append!(locations, get_definitions(word,v))
            end
            break
        end
    end

    response = JSONRPC.Response(get(r.id),locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end


