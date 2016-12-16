function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params
    documentation = get_local_hover(tdpp, server)
    if isempty(documentation) 
        word = get_word(tdpp, server, 1)
        if search(word, ".")!=0:-1
            sword = split(word, ".")
            mod = get_sym(join(sword[1:end-1], "."))
            if mod==nothing || !isa(mod, Module) || !isdefined(mod, Symbol(last(sword)))
                documentation = [""]
            else
                documentation = [string(Docs.doc(Docs.Binding(mod, Symbol(last(sword)))))]
            end
        elseif isdefined(Main, Symbol(word))
            documentation = [string(Docs.doc(Docs.Binding(Main, Symbol(word))))]
        else
            documentation = [""]
        end
    end

    response = JSONRPC.Response(get(r.id), Hover(documentation))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end


function get_local_hover(tdpp::TextDocumentPositionParams, server)
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    word = get_word(tdpp, server, 1)
    sword = Symbol.(split(word,'.'))
    
    ns = get_names(tdpp.textDocument.uri, server, offset)

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
        scope,t,def = ns[sym]
        return MarkedString.(["$scope: $t", string(striplocinfo(def))])
    end
    return []
end
