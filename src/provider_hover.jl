function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character)

    y, Y, I, O, scope = Parser.find_scope(doc.blocks.ast, offset)

    if y isa Parser.IDENTIFIER
        entry = get_cache_entry(string(y.val), server, [])
        documentation = entry[1] != :EMPTY ? Any[entry[2]] : []
        if !isempty(scope)
            for v in scope
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
        documentation = ["Hover at $(Expr(y))"]
    end
    response = JSONRPC.Response(get(r.id), Hover(documentation))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end


# function get_local_hover(word, ns, server)
#     sword = Symbol.(split(word,'.'))
    
#     if length(sword)>1
#         t = get_type(sword[1], ns)
#         for i = 2:length(sword)
#             fn = get_fields(t, ns)
#             if sword[i] in keys(fn)
#                 t = fn[sword[i]]
#             else
#                 t = :Any
#             end
#         end
#         t = Symbol(t)
#         return t==:Any ? [] : MarkedString.(["$t"])
#     elseif sword[1] in keys(ns.list)
#         v = ns.list[sword[1]]
#         if isa(v, LocalVar)
#             if v.t==:DataType
#                 return ["DataType"; MarkedString(striplocinfo(v.def))]
#             elseif v.t==:Function
#                 return [MarkedString("Function")]
#             else
#                 return ["$(v.t)", MarkedString(string(striplocinfo(v.def)))]
#             end
#         elseif isa(v, Dict)
#             return ["Module: $word"]
#         else
#             return ["$(v[1])", v[2]]
#         end

#     end
#     return []
# end
