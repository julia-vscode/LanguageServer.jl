type SymbolInformation 
    name::String 
    kind::Int 
    location::Location 
end 
 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    uri = r.params.textDocument.uri 
    blocks = server.documents[uri].blocks 
    lb = get_linebreaks(server.documents[uri].data)

    syms = SymbolInformation[]
    getsyminfo(blocks, syms, lb, uri)

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end 
 
function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params) 
    return DocumentSymbolParams(params) 
end

function getsyminfo(blocks, syms, lb, uri, prefix="") 
    for b in blocks.args
        name, t, loc = getname(b)
        if t==:Module
            getsyminfo(b.args[3], syms, lb, uri, string(name))
        elseif t==:Function
            push!(syms, SymbolInformation(string(prefix,".",name), 12, Location(uri, Range(findfirst(x->x>first(loc), lb)-1)))) 
        elseif t==:DataType 
            push!(syms, SymbolInformation(string(prefix,".",name), 5, Location(uri, Range(findfirst(x->x>first(loc), lb)-1)))) 
        elseif name!=:nothing 
            push!(syms, SymbolInformation(string(prefix,".",name), 13, Location(uri, Range(findfirst(x->x>first(loc), lb)-1)))) 
        end 
    end 
end