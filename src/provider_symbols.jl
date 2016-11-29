type SymbolInformation 
    name::String 
    kind::Int 
    location::Location 
end 
 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    uri = r.params.textDocument.uri 
    blocks = server.documents[uri].blocks 

    syms = SymbolInformation[]
    getsyminfo(blocks, syms, uri, server.documents[uri])

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end 
 
function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params) 
    return DocumentSymbolParams(params) 
end

function getsyminfo(blocks, syms, uri , doc, prefix="") 
    for b in blocks.args
        name, t, loc = getname(b)
        if t==:Module
            getsyminfo(b.args[3], syms, uri, doc, string(name))
        elseif t==:Function            
            push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 12, Location(uri, Range(get_position_at(doc, first(loc))[1])))) 
        elseif t==:DataType 
            push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 5, Location(uri, Range(get_position_at(doc, first(loc))[1])))) 
        elseif name!=:nothing 
            push!(syms, SymbolInformation(string(isempty(prefix) ? "" : prefix*".",name), 13, Location(uri, Range(get_position_at(doc, first(loc))[1]))))
        end 
    end 
end