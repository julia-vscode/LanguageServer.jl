function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    uri = r.params.textDocument.uri 
    doc = server.documents[URI2(uri)]
    syms = SymbolInformation[]
    s = toplevel(doc, server, false)
    for k in keys(s.symbols)
        for vl in s.symbols[k]
            if vl.v.t == :Function
                id = string(Expr(vl.v.val isa EXPR{CSTParser.FunctionDef} ? vl.v.val.args[2] : vl.v.val.args[1]))
            else
                id = string(vl.v.id)
            end
            ws_offset = CSTParser.trailing_ws_length(vl.v.val)
            loc1 = vl.loc.start:vl.loc.stop - ws_offset
            push!(syms, SymbolInformation(id, SymbolKind(vl.v.t), Location(vl.uri, Range(doc, loc1))))
        end
    end
    
    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end


function process(r::JSONRPC.Request{Val{Symbol("workspace/symbol")},WorkspaceSymbolParams}, server) 
    syms = SymbolInformation[]
    query = r.params.query
    for doc in values(server.documents)
        uri = doc._uri
        s = toplevel(doc, server, false)
        for k in keys(s.symbols)
            for vl in s.symbols[k]
                if ismatch(Regex(query, "i"), string(vl.v.id))
                    if vl.v.t == :Function
                        id = string(Expr(vl.v.val isa EXPR{CSTParser.FunctionDef} ? vl.v.val.args[2] : vl.v.val.args[1]))
                    else
                        id = string(vl.v.id)
                    end
                    push!(syms, SymbolInformation(id, SymbolKind(vl.v.t), Location(vl.uri, Range(doc, vl.loc))))
                end
            end
        end
    end

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/symbol")}}, params)
    return WorkspaceSymbolParams(params) 
end
