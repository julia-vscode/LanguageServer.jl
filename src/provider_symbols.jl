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
        SymbolInformation(string(v[1].id), SymbolKind(v[1].t), Location(uri, rng))
    end

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end
