function process(r::JSONRPC.Request{Val{Symbol("textDocument/signatureHelp")}, TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    word = get_word(tdpp, server)
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    str = get_line(tdpp, server)
    pos = pos0 = min(length(str), tdpp.position.character)
    io = IOBuffer(str)
    
    line = []
    cnt = 0
    while cnt < pos && !eof(io)
        cnt += 1
        push!(line, read(io, Char))
    end
    
    arg = b = 0
    word = "" 
    while pos > 1
        if line[pos] == '(' 
            if b == 0
                word = get_word(tdpp, server, pos - pos0 - 1)
                break
            elseif b > 0
                b -= 1
            end
        elseif line[pos] == ',' && b == 0
            arg += 1
        elseif line[pos] == ')'
            b += 1
        end
        pos -= 1
    end
    
    
    if word == ""
        response = JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id))))
    else
        y, Y, I, O, scope, modules = get_scope(doc, offset, server)
        sigs = get_signatures(word, get_cache_entry(word, server, modules))
        for (v, loc, uri) in scope
            if word == string(v.id) && v.t == :Function
                sig_loc = v.val[1] isa CSTParser.KEYWORD{CSTParser.Tokens.FUNCTION} ? 2 : 1
                push!(sigs.signatures, SignatureInformation(string(Expr(v.val[sig_loc])), "", [ParameterInformation(string(p.id)) for p in v.val[sig_loc].defs]))
            end
        end
        
        signatureHelper = SignatureHelp(filter(s->length(s.parameters) > arg, sigs.signatures), 0, arg)
        response = JSONRPC.Response(get(r.id), signatureHelper)
    end
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/signatureHelp")}}, params)
    return TextDocumentPositionParams(params)
end
