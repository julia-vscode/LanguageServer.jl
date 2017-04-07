type SymbolInformation 
    name::String 
    kind::Int 
    location::Location 
end 
 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    uri = r.params.textDocument.uri 
    doc = server.documents[uri]
    syms = map(Parser.get_symbols(doc.blocks.ast)) do v
        rng = Range(Position(get_position_at(doc, first(v[2]))..., one_based=true), Position(get_position_at(doc, last(v[2]))..., one_based=true))

        if v[1].t == :Function
            id = string(Expr(v[1].val.head isa Parser.KEYWORD{Parser.Tokens.FUNCTION} ? v[1].val[2] : v[1].val[1]))
        else
            id = string(v[1].id)
        end

        SymbolInformation(id, SymbolKind(v[1].t), Location(uri, rng))
    end

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end
