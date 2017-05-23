function process(r::JSONRPC.Request{Val{Symbol("textDocument/signatureHelp")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    word = get_word(tdpp, server)
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    str = get_line(tdpp, server)
    pos = pos0 = min(length(str), tdpp.position.character)
    io = IOBuffer(str)
    
    line = Char[]
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

    if isempty(word)
        response = JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id))))
    else
        y, s, modules, current_namespace = get_scope(doc, offset, server)
        x = get_cache_entry(parse(word), server, modules)

        sigs = SignatureHelp(SignatureInformation[], 0, 0)
        
        for m in methods(x)
            args = Base.arg_decl_parts(m)[2]
            p_sigs = [join(string.(p), "::") for p in args[2:end]]
            desc = string(m)
            PI = map(ParameterInformation, p_sigs)
            push!(sigs.signatures, SignatureInformation(desc, "", PI))
        end

        for (v, loc, uri) in s.symbols
            if v.t == :Function && (word == string(v.id) || (v.id isa Expr && v.id.head == :. && v.id.args[1] == current_namespace && word == string(v.id.args[2].value)))
                sig = CSTParser._get_fsig(v.val)
                push!(sigs.signatures, SignatureInformation(string(Expr(sig)), "", [ParameterInformation(string(p.id)) for p in sig.defs]))
            end
        end
        
        signatureHelper = SignatureHelp(filter(s -> length(s.parameters) > arg, sigs.signatures), 0, arg)
        response = JSONRPC.Response(get(r.id), signatureHelper)
    end
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/signatureHelp")}}, params)
    return TextDocumentPositionParams(params)
end
