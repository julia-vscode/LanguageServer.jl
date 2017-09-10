function process(r::JSONRPC.Request{Val{Symbol("textDocument/signatureHelp")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, r.params.textDocument.uri)
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    y, s = scope(doc, offset, server)
    if y isa PUNCTUATION{Tokens.RPAREN}
        return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
    elseif length(s.stack) > 0 && last(s.stack) isa EXPR{Call}
        fcall = s.stack[end]
        fname = CSTParser._get_fname(last(s.stack))
        x = get_cache_entry(fname, server, s)
    elseif length(s.stack) > 1 && s.stack[end] isa PUNCTUATION{Tokens.COMMA} && s.stack[end-1] isa EXPR{Call}
        fcall = s.stack[end-1]
        fname = CSTParser._get_fname(fcall)
        x = get_cache_entry(fname, server, s)
    else
        return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
    end
    arg = sum(!(a isa PUNCTUATION) for a in fcall.args) - 1

    sigs = SignatureHelp(SignatureInformation[], 0, 0)

    for m in methods(x)
        args = Base.arg_decl_parts(m)[2]
        p_sigs = [join(string.(p), "::") for p in args[2:end]]
        desc = string(m)
        PI = map(ParameterInformation, p_sigs)
        push!(sigs.signatures, SignatureInformation(desc, "", PI))
    end
    
    
    nsEy = join(vcat(s.namespace, str_value(fname)), ".")
    if haskey(s.symbols, nsEy)
        for vl in s.symbols[nsEy]
            if vl.v.t == :function
                sig = CSTParser._get_fsig(vl.v.val)
                Ps = ParameterInformation[]
                for j = 2:length(sig.args)
                    if sig.args[j] isa EXPR{CSTParser.Parameters}
                        for parg in sig.args[j].args
                            if !(sig.args[j] isa PUNCTUATION)
                                arg_id = str_value(CSTParser._arg_id(sig.args[j]))
                                arg_t = CSTParser.get_t(sig.args[j])
                                push!(Ps, ParameterInformation(string(arg_id,"::",arg_t)))
                            end
                        end
                    else
                        if !(sig.args[j] isa PUNCTUATION)
                            arg_id = str_value(CSTParser._arg_id(sig.args[j]))
                            arg_t = CSTParser.get_t(sig.args[j])
                            push!(Ps, ParameterInformation(string(arg_id,"::",arg_t)))
                        end
                    end
                end
                push!(sigs.signatures, SignatureInformation(string(Expr(sig)), "", Ps))
            end
        end
    end
    

    signatureHelper = SignatureHelp(filter(s -> length(s.parameters) > arg, sigs.signatures), 0, arg)
    response = JSONRPC.Response(get(r.id), signatureHelper)
    
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/signatureHelp")}}, params)
    return TextDocumentPositionParams(params)
end
