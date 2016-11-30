function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params
    documentation = get_local_hover(tdpp, server)
    isempty(documentation) && (documentation = get_docs(r.params, server))

    response = JSONRPC.Response(get(r.id), Hover(documentation))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end


function get_local_hover(tdpp::TextDocumentPositionParams, server)
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    word = get_word(tdpp, server)
    sword = Symbol.(split(word,'.'))
    ex, ns = get_namespace(doc.blocks, offset)

    if length(sword)>1
        t = get_type(sword[1], ns)
        for i = 2:length(sword)
            fn = get_fields(t, ns, doc.blocks)
            if sword[i] in keys(fn)
                t = fn[sword[i]]
            else
                t = :Any
            end
        end
        t = Symbol(t)
        return t==:Any ? [] : MarkedString.(["$t"]) 
    end
        
    sym = Symbol(word)

    
    if sym in keys(ns)
        scope,t,loc = ns[sym]
        lno,cno = get_position_at(doc, first(loc))
        line = get_line(doc, lno)
        while line[cno]=='\n'
            lno+=1
            cno = 1
            line = get_line(doc, lno)
        end
        title = string("$scope: ", t," at ", lno)
        return MarkedString.([title, strip(line)])
     end
    return []
end