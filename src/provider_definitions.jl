function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character + 1)
    word = get_word(tdpp, server)
    y, s, modules, current_namespace = scope(doc, offset, server)

    locations = Location[]
    if y isa EXPR{CSTParser.IDENTIFIER} || y isa EXPR{OP} where OP <: CSTParser.OPERATOR
        x = get_cache_entry(Expr(y), server, s)
    elseif y isa EXPR{CSTParser.Quotenode} && last(s.stack) isa CSTParser.EXPR{CSTParser.BinarySyntaxOpCall} && last(s.stack).args[2] isa EXPR{OP} where OP <: CSTParser.OPERATOR{16,Tokens.DOT}
        x = get_cache_entry(Expr(last(s.stack)), server, s)
    else
        x = nothing
    end
    for m in methods(x)
        file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
        push!(locations, Location(is_windows() ? "file:///$(URIParser.escape(replace(file, '\\', '/')))" : "file:$(file)", Range(m.line - 1, 0, m.line, 0)))
    end
    
    
    if y != nothing
        if y isa EXPR{CSTParser.Quotenode} && last(s.stack) isa CSTParser.EXPR{CSTParser.BinarySyntaxOpCall} && last(s.stack).args[2] isa EXPR{OP} where OP <: CSTParser.OPERATOR{16,Tokens.DOT}
            Ey = Expr(last(s.stack))
        else
            Ey = Expr(y)
        end
        nsEy = join(vcat(s.namespace, Ey), ".")
        if haskey(s.symbols, nsEy)
            for (v, loc, uri) in s.symbols[nsEy]
                if Ey == v.id || (v.id isa Expr && v.id.head == :. && v.id.args[1] == current_namespace && Ey == v.id.args[2].value)
                    doc1 = server.documents[uri]
                    ws_offset = trailing_ws_length(get_last_token(v.val))
                    loc1 = loc.start:loc.stop - ws_offset
                    push!(locations, Location(uri, Range(doc1, loc1)))
                end
            end
        end
    end

    response = JSONRPC.Response(get(r.id), locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end

# NEEDS FIX: This is in CSTParser next release, remove.
function get_last_token(x::CSTParser.EXPR)
    if isempty(x.args)
        return x
    else
        return get_last_token(last(x.args))
    end
end

function trailing_ws_length(x::CSTParser.EXPR{CSTParser.IDENTIFIER})
    x.span - sizeof(x.val)
end

function trailing_ws_length(x::CSTParser.EXPR{P}) where P <: CSTParser.PUNCTUATION
    x.span - 1
end

function trailing_ws_length(x::CSTParser.EXPR{L}) where L <: CSTParser.LITERAL
    x.span - sizeof(x.val)
end

function trailing_ws_length(x::CSTParser.EXPR{OP}) where OP <: CSTParser.OPERATOR{P,K,dot} where {P,K,dot}
    x.span - sizeof(string(CSTParser.UNICODE_OPS_REVERSE[K])) - dot
end

function trailing_ws_length(x::CSTParser.EXPR{K}) where K <: CSTParser.KEYWORD{T} where T
    x.span - sizeof(string(T))
end
