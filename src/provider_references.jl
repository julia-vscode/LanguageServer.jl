# Find references to an identifier. Only works in file.
function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    y, s, modules, current_namespace = get_scope(doc, offset, server)
    
    locations = Location[]
    if y isa EXPR{CSTParser.IDENTIFIER}
        yid = CSTParser.get_id(y).val
        s_id = findlast(s -> s[1].id == Symbol(CSTParser.get_id(y).val), s.symbols)
        if s_id > 0
            V, LOC, uri = s.symbols[s_id]
            locs = find_ref(doc.code.ast, V, LOC)
            for loc in locs
                push!(locations, Location(uri, Range(doc, loc)))
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
    for (i, a) in enumerate(x.args)
        if a isa CSTParser.EXPR
            for v in a.defs
                push!(scope, (v, offset + (1:a.span)))
            end
            if CSTParser.contributes_scope(a)
                CSTParser.get_symbols(a, offset, scope)
            end
        end
        _find_ref(a, V, LOC, offset, copy(scope), refs)
        offset += a.span
    end
end


function _find_ref(x::EXPR{CSTParser.Quotenode}, V, LOC, offset, scope, refs) end
function _find_ref(x::EXPR{CSTParser.ERROR}, V, LOC, offset, scope, refs) end

function _find_ref(x::EXPR{CSTParser.IDENTIFIER}, V, LOC, offset, scope, refs)
    if Symbol(x.val) == V.id
        scope_id = findlast(s -> s[1].id == V.id, scope)
        if scope_id > 0
            v, loc = scope[scope_id]
            if v == V && loc == LOC
                push!(refs, offset + (1:x.span))
            end
        end
    end
end

function find_ref(x::EXPR, V, LOC)
    offset = 0
    scope = Tuple{CSTParser.Variable,UnitRange{Int}}[]
    refs = UnitRange{Int}[]
    _find_ref(x, V, LOC, offset, scope, refs)
    return refs
end
