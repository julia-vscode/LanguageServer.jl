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
    ns = get_names(blocks, 1, server).list
    for (name, v) in ns
        if v.t==:Module
            v.def.args[3].typ = v.def.typ
            getsyminfo(v.def.args[3], syms, uri, doc, server, string(name))
        else 
            k = SymbolKind(v.t)
            if v.t==:Function && isa(v.def.args[1], Expr)
                start = Position(get_position_at(doc, first(v.def.args[1].typ))..., one_based=true)
            else
                start = Position(get_position_at(doc, max(1, first(v.def.typ)))..., one_based=true)
            end
            stop = Position(get_position_at(doc, last(v.def.typ))..., one_based=true)

            
            push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), k, Location(uri, Range(start, stop))))
        end
    end
end
