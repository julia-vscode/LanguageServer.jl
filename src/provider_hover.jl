function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, r.params.textDocument.uri)
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)

    y, s = scope(doc, offset, server)

    if y isa EXPR{CSTParser.IDENTIFIER} || y isa EXPR{OP} where OP <: CSTParser.OPERATOR
        x = get_cache_entry(y, server, s)
        documentation = x == nothing ? Any[] : Any[string(Docs.doc(x))] 
        get_scope_entry_doc(y, s, documentation)
    elseif y isa EXPR{CSTParser.Quotenode} && last(s.stack) isa EXPR{CSTParser.BinarySyntaxOpCall} && last(s.stack).args[2] isa EXPR{CSTParser.OPERATOR{16,Tokens.DOT,false}}
        x = get_cache_entry(last(s.stack), server, s)
        documentation = x == nothing ? Any[] : Any[string(Docs.doc(x))]
        get_scope_entry_doc(last(s.stack), s, documentation)
    elseif y isa EXPR{CSTParser.LITERAL}
        documentation = [string(lowercase(string(typeof(y).parameters[1])), ":"), MarkedString(string(Expr(y)))]
    elseif y isa EXPR{CSTParser.KEYWORD{Tokens.END}} && !isempty(s.stack)
        expr_type = Expr(last(s.stack).args[1])
        documentation = [MarkedString("Closes `$expr_type` expression")]
    elseif y isa EXPR{CSTParser.PUNCTUATION{Tokens.RPAREN}} && !isempty(s.stack)
        last_ex = last(s.stack)
        if last_ex isa EXPR{CSTParser.Call}
            documentation = [MarkedString("Closes `$(Expr(last_ex.args[1]))` call")]
        elseif last_ex isa EXPR{CSTParser.TupleH}
            documentation = [MarkedString("Closes a tuple")]
        else
            documentation = [""]
        end
    elseif y != nothing && !(y isa EXPR{<:CSTParser.PUNCTUATION})
        documentation = [string(Expr(y))]
    else
        documentation = [""]
    end
    response = JSONRPC.Response(get(r.id), Hover(unique(documentation)))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end

function get_scope_entry_doc(y::EXPR, s::TopLevelScope, documentation)
    Ey = Expr(y)
    nsEy = join(vcat(s.namespace, Ey), ".")
    if haskey(s.symbols, nsEy)
        for (v, loc, uri) in s.symbols[nsEy]
            if v.t == :Any
                push!(documentation, MarkedString("julia", string(Expr(v.val))))
            elseif v.t == :Function
                push!(documentation, MarkedString("julia", string(Expr(CSTParser._get_fsig(v.val)))))
            else
                push!(documentation, MarkedString(string(v.t)))
            end
        end
    end
end
