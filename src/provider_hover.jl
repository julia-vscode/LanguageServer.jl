function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params

    documentation = get_local_hover(tdpp, server)
    
    isempty(documentation) && (documentation = get_docs(r.params, server))
         
    response = JSONRPC.Response(get(r.id), Hover(documentation))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end


function get_local_hover(tdpp::TextDocumentPositionParams, server)
    io = IOBuffer(server.documents[tdpp.textDocument.uri].data)
    for i = 1:tdpp.position.line
        readuntil(io,0x0a)
    end
    for i = 1:tdpp.position.character
        read(io,1)
    end
    s = Symbol(get_word(tdpp, server))
    ex, vars = getnamespace(server.documents[tdpp.textDocument.uri].blocks, position(io))
    if s in keys(vars)
        scope,t,loc = vars[s]
        lb = get_linebreaks(server.documents[tdpp.textDocument.uri].data)
        lno = findfirst(x->x>first(loc),lb)-1
        title = string("$scope: ", t," at ", lno)
        line = get_line(tdpp.textDocument.uri, lno-1, server)
        while isempty(line)
            lno+=1
            line = get_line(tdpp.textDocument.uri, lno-1, server)
            
        end
        return MarkedString.([title, strip(line)])
     end
    return []
end