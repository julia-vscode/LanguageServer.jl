import CSTParser: IDENTIFIER, INSTANCE, QUOTENODE, LITERAL, EXPR, ERROR, KEYWORD, HEAD, Tokens, Variable, FILE
import CSTParser: TOPLEVEL, STRING, BLOCK, CALL, NOTHING

function get_scope(doc::Document, offset::Int, server)
    uri = doc._uri
    stack, inds, offsets = CSTParser.SyntaxNode[], Int[], Int[]
    scope, modules = Tuple{Variable,UnitRange,String}[], Union{Symbol,Expr}[]
    # Search for includes of this file
    namespace = [:NOTHING]
    for (uri1, doc1) in server.documents
        if any(d[1] == uri for d in doc1.code.includes)
            for (incl, ns) in doc1.code.includes
                if incl == uri && !isempty(ns)
                    namespace = ns
                end
            end
            get_symbols_follow(doc1.code.ast, offset, scope, uri1, server)
        end
    end

    current_namespace = repack_dot(namespace)
    
    y = _find_scope(doc.code.ast, offset, stack, inds, offsets, scope, uri, server)

    for (v, loc, uri1) in scope
        if v.t == :IMPORTS && v.id isa Expr && v.id.args[1] isa Symbol && v.id.args[1] != :.
            put!(server.user_modules, v.id.args[1])
            push!(modules, v.id.args[1])
        end
    end
    return y, stack, inds, offsets, scope, modules, current_namespace
end

function _find_scope(x::EXPR, n::Int, stack::Vector, inds::Vector{Int}, offsets::Vector{Int}, scope, uri::String, server)
    if x.head == STRING
        return x
    elseif x.head isa KEYWORD{Tokens.USING} || x.head isa KEYWORD{Tokens.IMPORT} || x.head isa KEYWORD{Tokens.IMPORTALL} || (x.head == TOPLEVEL && all(x.args[i] isa EXPR && (x.args[i].head isa KEYWORD{Tokens.IMPORT} || x.args[i].head isa KEYWORD{Tokens.IMPORTALL} || x.args[i].head isa KEYWORD{Tokens.USING}) for i = 1:length(x.args)))
        for d in x.defs
            unshift!(scope, (d, sum(offsets) + (1:x.span), uri))
        end
        return x
    end
    offset = 0
    if n > x.span
        return NOTHING
    end
    push!(stack, x)
    for (i, a) in enumerate(x)
        if n > offset + a.span
            get_scope(a, sum(offsets) + offset, scope, uri, server)
            offset += a.span
        else
            if a isa EXPR
                for d in a.defs
                    push!(scope, (d, sum(offsets) + offset + (1:a.span), uri))
                end
            end
            push!(inds, i)
            push!(offsets, offset)
            if (x.head == FILE && length(stack) == 1 && first(stack).head == FILE) || (length(stack) > 2 && stack[end - 1].head isa KEYWORD{Tokens.MODULE} && stack[end].head == BLOCK)
                offset1 = sum(offsets) + a.span
                for j = i + 1:length(x)
                    get_scope(x[j], offset1, scope, uri, server)
                    offset1 += x[j].span
                end
            end
            return _find_scope(a, n - offset, stack, inds, offsets, scope, uri, server)
        end
    end
end

_find_scope(x::Union{QUOTENODE,INSTANCE,ERROR}, n::Int, stack::Vector, inds::Vector{Int}, offsets::Vector{Int}, scope, uri::String, server) = x

function get_scope(x, offset::Int, scope, uri::String, server) end

function get_scope(x::EXPR, offset::Int, scope, uri::String, server)
    for d in x.defs
        push!(scope, (d, offset + (1:x.span), uri))
    end
    if contributes_scope(x)
        for a in x
            get_scope(a, offset, scope, uri, server)
            offset += a.span
        end
    end

    if x.head == CALL && x.args[1] isa IDENTIFIER && x.args[1].val == :include && (x.args[2] isa LITERAL{Tokens.STRING} || x.args[2] isa LITERAL{Tokens.TRIPLE_STRING})
        file = Expr(x.args[2])
        if !startswith(file, "/")
            file = joinpath(dirname(uri), file)
        else
            file = filepath2uri(file)
        end
        if file in keys(server.documents)
            incl_syms = get_symbols_follow(server.documents[file].code.ast, 0, [], file, server)
            append!(scope, incl_syms)
        end
    end
end


contributes_scope(x) = false
function contributes_scope(x::EXPR)
    x.head isa KEYWORD{Tokens.BLOCK} ||
    x.head isa KEYWORD{Tokens.CONST} ||
    x.head isa KEYWORD{Tokens.GLOBAL} || 
    x.head isa KEYWORD{Tokens.IF} ||
    x.head isa KEYWORD{Tokens.LOCAL} ||
    x.head isa HEAD{Tokens.MACROCALL}
end

find_scope(x::ERROR, n::Int) = ERROR, [], [], [], [], []




function get_symbols_follow(x, offset::Int, symbols, uri, server) end
function get_symbols_follow(x::EXPR, offset::Int, symbols, uri, server)
    for a in x
        if a isa EXPR
            if a.head == CALL && a.args[1] isa IDENTIFIER && a.args[1].val == :include && (a.args[2] isa LITERAL{Tokens.STRING} || a.args[2] isa LITERAL{Tokens.TRIPLE_STRING})
                file = Expr(a.args[2])
                if !startswith(file, "/")
                    file = joinpath(dirname(uri), file)
                else
                    file = filepath2uri(file)
                end
                if file in keys(server.documents)
                    incl_syms = get_symbols_follow(server.documents[file].code.ast, 0, [], file, server)
                    append!(symbols, incl_syms)
                end
            end
            if !isempty(a.defs)
                for v in a.defs
                    push!(symbols, (v, offset + (1:a.span), uri))
                end
            end
            if contributes_scope(a)
                get_symbols_follow(a, offset, symbols, uri, server)
            end
            if a.head isa KEYWORD{Tokens.MODULE} || a.head isa KEYWORD{Tokens.MODULE}
                m_scope = get_symbols_follow(a[3], 0, [], uri, server)
                offset2 = offset + a[1].span + a[2].span
                for mv in m_scope
                    if mv[3] == uri
                        push!(symbols, (Variable(Expr(:(.), a.defs[1].id, QuoteNode(mv[1].id)), mv[1].t, mv[1].val), mv[2] + offset2, uri))
                    else
                        push!(symbols, (Variable(Expr(:(.), a.defs[1].id, QuoteNode(mv[1].id)), mv[1].t, mv[1].val), mv[2], mv[3]))
                    end
                    
                end
            end
        end
        offset += a.span
    end
    return symbols
end
