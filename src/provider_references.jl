import Tokenize.Tokens
# Find references to an identifier. Only works in file.
function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    y, Y, I, O, S = Parser.find_scope(doc.blocks.ast, offset)
    locations = Location[]
    if y isa Parser.IDENTIFIER
        yid = Parser.get_id(y).val
        s_id = findlast(s -> s[1].id == Parser.get_id(y).val, S)
        if s_id >0
            V, LOC = S[s_id]
            locs = find_ref(doc.blocks.ast, V, LOC)
            for loc in locs
                rng = Range(Position(get_position_at(doc, first(loc))..., one_based = true), Position(get_position_at(doc, last(loc))..., one_based = true))

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

function _find_ref(x::Parser.EXPR, V, LOC, offset, scope, refs)
    if x.head == Parser.STRING || 
        x.head isa Parser.KEYWORD{Tokens.USING} || 
        x.head isa Parser.KEYWORD{Tokens.IMPORT} || 
        x.head isa Parser.KEYWORD{Tokens.IMPORTALL} || 
        (x.head == Parser.TOPLEVEL && x.args[1] isa Parser.EXPR && (x.args[1].head isa Parser.KEYWORD{Tokens.IMPORT} || x.args[1].head isa Parser.KEYWORD{Tokens.IMPORTALL} || x.args[1].head isa Parser.KEYWORD{Tokens.USING}))
        return x
    end
    for (i, a) in enumerate(x)
        if a isa Parser.EXPR
            if !isempty(a.defs)
                for v in a.defs
                    push!(scope, (v, offset + (1:a.span)))
                end
            end
            if Parser.contributes_scope(a)
                Parser.get_symbols(a, offset, scope)
            end
        end
        _find_ref(a, V, LOC, offset, copy(scope), refs)
        offset += a.span
    end
end

function _find_ref(x::Union{Parser.QUOTENODE,Parser.INSTANCE,Parser.ERROR}, V, LOC, offset, scope, refs)

end

function _find_ref(x::Parser.IDENTIFIER, V, LOC, offset, scope, refs)
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

function find_ref(x::Parser.EXPR, V, LOC)
    offset = 0
    scope = []
    refs = []
    _find_ref(x, V, LOC, offset, scope, refs)
    return refs
end


