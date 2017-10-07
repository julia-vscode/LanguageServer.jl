# Find location of default datatype constructor
const DefaultTypeConstructorLoc= let def = first(methods(Int))
    Base.find_source_file(string(def.file)), def.line
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, r.params.textDocument.uri)
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character + 1)
    y, s = scope(doc, offset, server)
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")


    locations = Location[]
    if y isa IDENTIFIER || y isa OPERATOR
        if length(s.stack) > 1 && s.stack[end] isa EXPR{Quotenode} && s.stack[end-1] isa BinarySyntaxOpCall && CSTParser.is_dot(s.stack[end-1].op)
            x = get_cache_entry(s.stack[end-1], server, s)
        else
            x = get_cache_entry(y, server, s)
        end
    elseif y isa EXPR{Quotenode} && last(s.stack) isa BinarySyntaxOpCall && CSTParser.is_dot(last(s.stack).args[2])
        x = get_cache_entry(last(s.stack), server, s)
    else
        x = nothing
    end
    for m in methods(x)
        file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
        if (file, m.line) == DefaultTypeConstructorLoc
            continue
        end
        push!(locations, Location(is_windows() ? "file:///$(URIParser.escape(replace(file, '\\', '/')))" : "file:$(file)", Range(m.line - 1, 0, m.line, 0)))
    end
    
    
    if y != nothing
        if y isa EXPR{CSTParser.Quotenode} && last(s.stack) isa BinarySyntaxOpCall && CSTParser.is_dot(last(s.stack).args[2])
            Ey = Expr(last(s.stack))
        else
            Ey = Expr(y)
        end
        nsEy = join(vcat(s.namespace, Ey), ".")
        if haskey(s.symbols, nsEy)
            for vl in s.symbols[nsEy]
                if Ey == vl.v.id || (vl.v.id isa Expr && vl.v.id.head == :. && vl.v.id.args[1] == ns && Ey == vl.v.id.args[2].value)
                    doc1 = server.documents[vl.uri]
                    ws_offset = CSTParser.trailing_ws_length(vl.v.val)
                    loc1 = vl.loc.start:vl.loc.stop - ws_offset
                    push!(locations, Location(vl.uri, Range(doc1, loc1)))
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
