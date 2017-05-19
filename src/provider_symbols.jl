function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    uri = r.params.textDocument.uri 
    doc = server.documents[uri]
    syms = SymbolInformation[]
    s = get_toplevel(doc, server, false)

    for (v, loc, uri1) in s.symbols
        if v.t == :IMPORTS
            continue
        end
        if v.t == :Function
            id = string(Expr(v.val.head isa CSTParser.KEYWORD{CSTParser.Tokens.FUNCTION} ? v.val[2] : v.val[1]))
        else
            id = string(v.id)
        end

        push!(syms, SymbolInformation(id, SymbolKind(v.t), Location(uri, Range(doc, loc))))
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
    for (uri, doc) in server.documents
        s = get_toplevel(doc, server, false)
        for (v, loc, uri1) in s.symbols
            if ismatch(Regex(query, "i"), string(v.id))
                if v.t == :Function
                    id = string(Expr(v.val.head isa CSTParser.KEYWORD{CSTParser.Tokens.FUNCTION} ? v.val[2] : v.val[1]))
                else
                    id = string(v.id)
                end
                push!(syms, SymbolInformation(id, SymbolKind(v.t), Location(uri, Range(doc, loc))))
            end
        end
    end

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/symbol")}}, params)
    return WorkspaceSymbolParams(params) 
end
