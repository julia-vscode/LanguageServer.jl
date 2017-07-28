function scope(doc::Document, offset::Int, server)
    uri = doc._uri

    # Find top file of include tree
    path, namespace = findtopfile(uri, server)
    
    s = TopLevelScope(ScopePosition(uri, offset), ScopePosition(last(path), 0), false, Dict(), EXPR[], Symbol[], true, true, Dict(:toplevel => []), [])
    toplevel(server.documents[last(path)].code.ast, s, server)
    

    s.current = ScopePosition(uri)
    s.namespace = namespace
    y = _scope(doc.code.ast, s, server)

    current_namespace = isempty(s.namespace) ? "toplevel" : join(reverse(s.namespace), ".")
    
    modules = Symbol[]
    for (v, loc, uri1) in s.imports[current_namespace == "toplevel" ? "toplevel" : haskey(s.imports, current_namespace) ? current_namespace : "toplevel"]
        if !(v.args[1] in modules) && v.args[1] isa Symbol
            push!(server.user_modules, (v.args[1], uri1, loc))
            push!(modules, v.args[1])
        end
    end
    
    return y, s, modules, current_namespace
end



_scope(x::EXPR{T}, s::TopLevelScope, server) where T <: Union{IDENTIFIER,Quotenode,LITERAL} = x
_scope(x::EXPR{CSTParser.KEYWORD{Tokens.END}}, s::TopLevelScope, server) = x
_scope(x::EXPR{CSTParser.PUNCTUATION{Tokens.RPAREN}}, s::TopLevelScope, server) = x

function _scope(x::EXPR, s::TopLevelScope, server)
    if ismodule(x)
        toplevel_symbols(x, s)
        push!(s.namespace, x.defs[1].id)
    end
    if s.current.offset + x.span < s.target.offset
        return NOTHING
    end
    push!(s.stack, x)
    for (i, a) in enumerate(x.args)
        if s.current.offset + a.span < s.target.offset
            !s.intoplevel && get_scope(a, s, server)
            s.current.offset += a.span
        else
            if !s.intoplevel && a isa EXPR
                toplevel_symbols(a, s)
            end
            if !contributes_scope(a) && s.intoplevel
                s.intoplevel = false
            end
            return _scope(a, s, server)
        end
    end
end



function get_scope(x, s::TopLevelScope, server) end

function get_scope(x::EXPR, s::TopLevelScope, server)
    offset = s.current.offset
    toplevel_symbols(x, s)
    if contributes_scope(x)
        for a in x.args
            get_scope(a, s, server)
            offset += a.span
        end
    end

    if isincludable(x)
        file = Expr(x.args[3])
        file = isabspath(file) ? filepath2uri(file) : joinpath(dirname(s.current.uri), normpath(file))
        
        file in s.path && return
        
        if file in keys(server.documents)
            oldpos = s.current
            s.current = ScopePosition(file, 0)
            incl_syms = toplevel(server.documents[file].code.ast, s, server)
            s.current = oldpos
        end
    end
end

