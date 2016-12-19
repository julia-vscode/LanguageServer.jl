function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    word = get_word(tdpp, server)
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character)
    ns = get_names(tdpp.textDocument.uri, offset, server)

    documentation = get_local_hover(word, ns, server)
    modules = []
    if isempty(documentation) 
        documentation = [get_cache_entry(word, server, modules)[2]]
    end

    response = JSONRPC.Response(get(r.id), Hover(documentation))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end


function get_local_hover(word, ns, server)
    sword = Symbol.(split(word,'.'))
    
    if length(sword)>1
        t = get_type(sword[1], ns)
        for i = 2:length(sword)
            fn = get_fields(t, ns)
            if sword[i] in keys(fn)
                t = fn[sword[i]]
            else
                t = :Any
            end
        end
        t = Symbol(t)
        return t==:Any ? [] : MarkedString.(["$t"])
    elseif sword[1] in keys(ns)
        scope,t,def = ns[sword[1]]
        return MarkedString.(["$scope: $t", string(striplocinfo(def))])
    end
    return []
end
