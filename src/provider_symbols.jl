type SymbolInformation 
    name::String 
    kind::Int 
    location::Location 
end 
 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    uri = r.params.textDocument.uri 
    doc = server.documents[uri]

    syms = SymbolInformation[]
    getsyminfo(doc.blocks, syms, uri, doc)

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end

function getsyminfo(blocks, syms, uri , doc, prefix="") 
    ns = get_names(blocks, 0)
    for (name, (s, t, loc, def)) in ns
        if t==:Module
            getsyminfo(def, syms, uri, doc, string(name))
        elseif t==:Function
            push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 12, Location(uri, Range(get_position_at(doc, first(loc))[1])))) 
        elseif t==:DataType
            push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 5, Location(uri, Range(get_position_at(doc, first(loc))[1])))) 
        else 
            push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 13, Location(uri, Range(get_position_at(doc, first(loc))[1]))))
        end
    end
end