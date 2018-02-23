
function StaticLint._follow_include(x, path, s, S::StaticLint.State{LanguageServerInstance})
    path = isabspath(path) ? path : joinpath(dirname(S.loc.path), path)
    if !haskey(S.fs.documents, URI2(filepath2uri(path)))
        return
    end

    if !isempty(S.target.path) && path == S.target.path
        S.in_target = true
    end
    x1 = S.fs.documents[URI2(filepath2uri(path))].code.ast
    old_Sloc = S.loc
    S.loc = StaticLint.Location(path, 0)
    StaticLint.trav(x1, s, S)
    S.loc = old_Sloc
    if !isempty(S.target.path) && S.loc.path != S.target.path
        S.in_target = false
    end
end

function StaticLint.trav(doc::Document, server, target = StaticLint.Location("", -1))
    path = uri2filepath(doc._uri)
    S = StaticLint.State{LanguageServerInstance}(StaticLint.Scope(), StaticLint.Location(path, 0), target, isempty(target.path) || (path == target.path), [], [], 0:0, false, Dict(path => StaticLint.File(path, nothing, [])), server, []);
    x = doc.code.ast
    StaticLint.trav(x, S.current_scope, S)
    StaticLint.find_bad_refs(S)

    return S
end



# function _get_includes(x, files = String[])
#     if StaticLint.isincludecall(x)
#         path = StaticLint.get_path(x)
#         isempty(path) && return
#         push!(files, path)
#     elseif x isa CSTParser.EXPR
#         for a in x.args
#             if !(x isa CSTParser.EXPR{CSTParser.Call})
#                 _get_includes(a, files)
#             end
#         end
#     end
#     return files
# end

function update_includes!(doc::Document)
    doc._includes = _get_includes(doc.code.ast)
    for (i, p) in enumerate(doc._includes)
        if !isabspath(p)
            doc._includes[i] = joinpath(dirname(doc._uri), p)
        end
    end
    
    return 
end

function update_includes!(server::LanguageServerInstance)
    for (_, doc) in server.documents
        update_includes!(doc)
    end
end

function get_token(x::CSTParser.LeafNode, target, offset = 0)
    return x
end

function get_token(x, target, offset = 0)
    for a in x
        if offset < target <= offset + a.fullspan
            return get_token(a, target, offset)
        else
            offset += a.fullspan
        end
    end
end

function get_stack(x::CSTParser.LeafNode, target, offset = 0, stack = [])
    push!(stack, x)
    return stack
end

function get_stack(x, target, offset = 0, stack = [])
    push!(stack, x)
    for a in x
        if offset < target <= offset + a.fullspan
            return get_stack(a, target, offset, stack)
        else
            offset += a.fullspan
        end
    end
    return stack
end

function get_scope(x, offset)
    for a in x.children
        if offset in a.loc.offset
            return get_scope(a, offset)
        end
    end
    return x
end

function get_names(cs, names = String[])
    append!(names, keys(cs.names))
    if cs.parent != nothing
        return get_names(cs.parent, names)
    else
        return names
    end
end

function find_ref(S, path, offset)
    for r in S.refs
        if r.loc.path == path && offset in r.loc.offset
            return r
        end
    end
    return StaticLint.MissingBinding(get_scope(S.current_scope, offset))
end

function similar_refs(path, offset, S, server)
    locations = Location[]
    for ref in S.refs
        if ref.loc.path == path && offset in ref.loc.offset
            b = ref.b
            for ref2 in S.refs
                if b == ref2.b
                    uri2 = filepath2uri(ref2.loc.path)
                    doc2 = server.documents[URI2(uri2)]
                    push!(locations, Location(uri2, Range(doc2, first(ref2.loc.offset) - 1:last(ref2.loc.offset))))
                end
            end
            break
        end
    end
    
    return locations
end