import Tokenize.Tokens
# Find references to an identifier. Only works in file.
function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    tdpp = r.params
    # uri = tdpp.textDocument.uri
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    y, Y, I, O, scope, modules, current_namespace = get_scope(doc, offset, server)
    locations = Location[]
    if y isa CSTParser.IDENTIFIER
        yid = CSTParser.get_id(y).val
        s_id = findlast(s -> s[1].id == CSTParser.get_id(y).val, scope)
        if s_id > 0
            V, LOC, uri = scope[s_id]
            locs = find_ref(doc.code.ast, V, LOC)
            for loc in locs
                start_l, start_c = get_position_at(doc, first(loc))
                end_l, end_c = get_position_at(doc, last(loc))
                rng = Range(start_l - 1, start_c - 1, end_l - 1, end_c)

                push!(locations, Location(uri, rng))
            end
        end
    end
    response = JSONRPC.Response(get(r.id), locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/references")}}, params)
    return ReferenceParams(params)
end

function _find_ref(x::CSTParser.EXPR, V, LOC, offset, scope, refs)
    if x.head == CSTParser.STRING || 
        x.head isa CSTParser.KEYWORD{Tokens.USING} || 
        x.head isa CSTParser.KEYWORD{Tokens.IMPORT} || 
        x.head isa CSTParser.KEYWORD{Tokens.IMPORTALL} || 
        (x.head == CSTParser.TOPLEVEL && all(x.args[i] isa CSTParser.EXPR && (x.args[i].head isa CSTParser.KEYWORD{Tokens.IMPORT} || x.args[i].head isa CSTParser.KEYWORD{Tokens.IMPORTALL} || x.args[i].head isa CSTParser.KEYWORD{Tokens.USING}) for i = 1:length(x.args)))
        return x
    end
    for (i, a) in enumerate(x)
        if a isa CSTParser.EXPR
            if !isempty(a.defs)
                for v in a.defs
                    push!(scope, (v, offset + (1:a.span)))
                end
            end
            if CSTParser.contributes_scope(a)
                CSTParser.get_symbols(a, offset, scope)
            end
        end
        _find_ref(a, V, LOC, offset, copy(scope), refs)
        offset += a.span
    end
end

function _find_ref(x::Union{CSTParser.QUOTENODE, CSTParser.INSTANCE, CSTParser.ERROR}, V, LOC, offset, scope, refs)

end

function _find_ref(x::CSTParser.IDENTIFIER, V, LOC, offset, scope, refs)
    if x.val == V.id
        scope_id = findlast(s -> s[1].id == V.id, scope)
        if scope_id > 0
            v, loc = scope[scope_id]
            if v == V && loc == LOC
                push!(refs, offset + (1:x.span))
            end
        end
    end
end

function find_ref(x::CSTParser.EXPR, V, LOC)
    offset = 0
    scope = []
    refs = []
    _find_ref(x, V, LOC, offset, scope, refs)
    return refs
end


