function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)

    y, s, modules, current_namespace = get_scope(doc, offset, server)

    if y isa EXPR{CSTParser.IDENTIFIER} || y isa EXPR{OP} where OP <: CSTParser.OPERATOR
        x = get_cache_entry(Expr(y), server, s)
        documentation = x == nothing ? Any[] : Any[string(Docs.doc(x))] 
        get_scope_entry_doc(y, s, current_namespace, documentation)
    elseif y isa EXPR{CSTParser.Quotenode} && last(s.stack) isa EXPR{CSTParser.BinarySyntaxOpCall} && last(s.stack).args[2] isa EXPR{OP} where OP <: CSTParser.OPERATOR{16,Tokens.DOT}
        x = get_cache_entry(Expr(last(s.stack)), server, s)
        documentation = x == nothing ? Any[] : Any[string(Docs.doc(x))]
        get_scope_entry_doc(last(s.stack), s, current_namespace, documentation)
    elseif y isa EXPR{CSTParser.LITERAL}
        documentation = [string(lowercase(string(typeof(y).parameters[1])), ":"), MarkedString(string(Expr(y)))]
    elseif y != nothing
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

function get_scope_entry_doc(y::EXPR, s::Scope, current_namespace, documentation)
    Ey = Expr(y)
    for (v, loc, uri) in s.symbols
        if Ey == v.id || (v.id isa Expr && v.id.head == :. && v.id.args[1] == current_namespace && Ey == v.id.args[2].value)
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
