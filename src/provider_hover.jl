function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, r.params.textDocument.uri)
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)

    y, s = scope(doc, offset, server)
    
    if y isa IDENTIFIER || y isa OPERATOR
        if length(s.stack) > 1 && s.stack[end] isa EXPR{Quotenode} && s.stack[end-1] isa BinarySyntaxOpCall && CSTParser.is_dot(s.stack[end-1].op)
            x = get_cache_entry(s.stack[end-1], server, s)
            documentation = x == nothing ? Any[] : Any[string(Docs.doc(x))]
            get_scope_entry_doc(s.stack[end-1], s, documentation)
        else
            x = get_cache_entry(y, server, s)
            documentation = x == nothing ? Any[] : Any[string(Docs.doc(x))] 
            get_scope_entry_doc(y, s, documentation)
        end
    elseif y isa LITERAL
        documentation = [MarkedString(string(Expr(y), "::", CSTParser.infer_t(y)))]
    elseif y isa KEYWORD{Tokens.END} && !isempty(s.stack)
        expr_type = Expr(last(s.stack).args[1])
        documentation = [MarkedString("Closes `$expr_type` expression")]
    elseif y isa PUNCTUATION{Tokens.RPAREN} && !isempty(s.stack)
        last_ex = last(s.stack)
        if last_ex isa EXPR{CSTParser.Call}
            documentation = [MarkedString("Closes `$(Expr(last_ex.args[1]))` call")]
        elseif last_ex isa EXPR{CSTParser.TupleH}
            documentation = [MarkedString("Closes a tuple")]
        else
            documentation = [""]
        end
    elseif y != nothing && !(y isa PUNCTUATION)
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

function get_scope_entry_doc(y, s::TopLevelScope, documentation)
    Ey = Expr(y)
    nsEy = join(vcat(s.namespace, Ey), ".")
    if haskey(s.symbols, nsEy)
        for vl in s.symbols[nsEy]
            if vl.v.t == :Any
                push!(documentation, MarkedString("julia", string(Expr(vl.v.val))))
            elseif vl.v.t == :Function
                push!(documentation, MarkedString("julia", string(Expr(CSTParser._get_fsig(vl.v.val)))))
            else
                push!(documentation, MarkedString(string(vl.v.t)))
            end
        end
    end
end
