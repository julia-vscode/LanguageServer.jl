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
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    word = get_word(tdpp, server)
    sword = split(word,'.')
    sym = Symbol(word)

    ex, vars = get_namespace(doc.blocks, offset)
    if sym in keys(vars)
        scope,t,loc = vars[sym]
        lno,cno = get_position_at(doc, first(loc))
        line = get_line(doc, lno)
        while line[cno]=='\n'
            lno+=1
            cno = 1
            line = get_line(doc, lno)
        end
        title = string("$scope: ", t," at ", lno)
        return MarkedString.([title, strip(line)])
     end
    return []
end