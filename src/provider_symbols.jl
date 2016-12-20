type SymbolInformation 
    name::String 
    kind::Int 
    location::Location 
end 
 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    uri = r.params.textDocument.uri 
    doc = server.documents[uri]
    parseblocks(doc, server)

    syms = SymbolInformation[]
    getsyminfo(doc.blocks, syms, uri, doc, server)

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end

function getsyminfo(blocks, syms, uri , doc, server, prefix="")
    ns = get_names(blocks, 1, server)
    for (name, v) in ns
        if isa(v, Tuple)
            (s, t, def) = v
            if t==:Module
                def.args[3].typ = def.typ
                getsyminfo(def.args[3], syms, uri, doc, server, string(name))
            elseif t==:Function
                push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 12, Location(uri, Range(get_position_at(doc, first(def.typ))[1])))) 
            elseif t==:DataType
                push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 5, Location(uri, Range(get_position_at(doc, first(def.typ))[1])))) 
            else
                push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 13, Location(uri, Range(get_position_at(doc, first(def.typ))[1]))))
            end
        end
    end
end