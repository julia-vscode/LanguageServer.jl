import CSTParser: IDENTIFIER, INSTANCE, QUOTENODE, LITERAL, EXPR, ERROR, KEYWORD, HEAD, Tokens, Variable, FILE
import CSTParser: TOPLEVEL, STRING, BLOCK, CALL, NOTHING

mutable struct ScopePosition
    uri::String
    offset::Int
    ScopePosition(uri = "",  offset = 0) = new(uri, offset)
end

mutable struct Scope
    target::ScopePosition
    current::ScopePosition
    symbols::Vector{VariableLoc}
    stack::Vector{CSTParser.SyntaxNode}
    stack_inds::Vector{Int}
    stack_offsets::Vector{Int}
    namespace::Vector
    hittarget::Bool
    followincludes::Bool
end
Scope(uri::String, followincludes = true) = Scope(ScopePosition(), ScopePosition(uri, 0), [], [], [], [], [], false, followincludes)


function get_scope(doc::Document, offset::Int, server)
    uri = doc._uri

    # Find top file of include tree
    path, namespace = findtopfile(uri, server)
    
    s = Scope(ScopePosition(uri, offset), ScopePosition(last(path), 0), [], [], [], [], namespace, false, true)
    get_toplevel(server.documents[last(path)].code.ast, s, server)
    scope = s.symbols

    s.current = ScopePosition(uri)
    y = _find_scope(doc.code.ast, s, server)
    offsets = s.stack_offsets
    scope = s.symbols
    inds = s.stack_inds
    stack = s.stack


    current_namespace = isempty(s.namespace) ? :NOTHING : repack_dot(s.namespace)

    # Get imported modules
    modules = get_imports(scope, server)

    # return y, stack, inds, offsets, scope, modules, current_namespace
    return y, s, modules, current_namespace
end

"""
    contributes_scope(x)
Checks whether the body of `x` is included in the toplevel namespace.
"""
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

"""
    isinclude(x)
Checks whether `x` is an expression that includes a file.
"""
isinclude(x) = false
function isinclude(x::EXPR) 
    x.head == CALL && x.args[1] isa IDENTIFIER && x.args[1].val == :include && (x.args[2] isa LITERAL{Tokens.STRING} || x.args[2] isa LITERAL{Tokens.TRIPLE_STRING})
end


"""
    isimport(x)
Checks whether `x` is an expression that imports a module.
"""
isimport(x) = false
function isimport(x::EXPR)
    x.head isa KEYWORD{Tokens.USING} || x.head isa KEYWORD{Tokens.IMPORT} || x.head isa KEYWORD{Tokens.IMPORTALL} || (x.head == TOPLEVEL && all(x.args[i] isa EXPR && (x.args[i].head isa KEYWORD{Tokens.IMPORT} || x.args[i].head isa KEYWORD{Tokens.IMPORTALL} || x.args[i].head isa KEYWORD{Tokens.USING}) for i = 1:length(x.args)))
end

"""
    ismodule(x)
Checks whether `x` is an expression that declares a module.
"""
ismodule(x) = false
function ismodule(x::EXPR)
    x.head isa KEYWORD{Tokens.MODULE} || x.head isa KEYWORD{Tokens.BAREMODULE}
end

function get_imports(S::Vector{VariableLoc}, server)
    modules = Union{Symbol,Expr}[]
    rmid = Int[]
    for (i, (v, loc, uri1)) in enumerate(S)
        if v.t == :IMPORTS && v.id isa Expr && v.id.args[1] isa Symbol && v.id.args[1] != :.
            put!(server.user_modules, v.id.args[1])
            push!(modules, v.id.args[1])
            push!(rmid, i)
        end
    end
    deleteat!(S, rmid)
    return modules
end


function get_toplevel(doc::Document, server, followincludes = true)
    s = Scope(doc._uri, followincludes)
    get_toplevel(doc.code.ast, s, server)
    return s
end

"""
    get_toplevel(x::EXPR, s::Scope, server)

Collects declared variables within an expression, stops if a target 
specified in `s` is met, will optionally follow includes.
"""
function get_toplevel(x::EXPR, s::Scope, server)
    if isimport(x)
        put_imports(x, s)
        return
    end
    for a in x
        offset = s.current.offset
        if s.hittarget
            return
        elseif (s.current.uri == s.target.uri && s.current.offset <= s.target.offset <= (s.current.offset + a.span)) && !(contributes_scope(a) || ismodule(a) || CSTParser.declares_function(a))
            s.hittarget = true 
            return
        end
        if a isa EXPR
            if s.followincludes && isinclude(a)
                get_include(a, s, server)
            end
            get_symbols(a, s)

            if ismodule(a)
                get_module(a, s, server)
            elseif contributes_scope(a)
                get_toplevel(a, s, server)
            end
            
        end
        s.current.offset = offset + a.span
    end
    return 
end

"""
    get_symbols(x, s::Scope)

Retrieves symbols bound by an expression, appends them to s.symbols.
"""
function get_symbols(x, s::Scope) end
function get_symbols(x::EXPR, s::Scope)
    for v in x.defs
        push!(s.symbols, (v, s.current.offset + (1:x.span), s.current.uri))
    end
end

"""
    get_include(x, s, server)

Adds the contents of a file (in the workspace) to the current scope.
"""
function get_include(x::EXPR, s::Scope, server)
    file = Expr(x.args[2])
    if !isabspath(file)
        file = joinpath(dirname(s.current.uri), file)
    else
        file = filepath2uri(file)
    end
    if file in keys(server.documents)
        oldpos = s.current
        s.current = ScopePosition(file, 0)
        incl_syms = get_toplevel(server.documents[file].code.ast, s, server)
        s.current = oldpos
    end
end

function put_imports(x::EXPR, s::Scope)
    for d in x.defs
        unshift!(s.symbols, (d, sum(s.stack_offsets) + (1:x.span), s.current.uri))
    end
end


"""
    get_module(x::EXPR, s::Scope, server)

A wrapper around get_toplevel that adds the module name prefix to declared 
variables.
"""
function get_module(x::EXPR, s::Scope, server)
    s_module = Scope(s.target, ScopePosition(s.current.uri, s.current.offset + x.head.span + x.args[2].span), [], [], [], [], [], s.hittarget, s.followincludes)
    get_toplevel(x[3], s_module, server)
    offset2 = s.current.offset + x[1].span + x[2].span
    for (v, loc, uri) in s_module.symbols
        if v.t == :IMPORTS
            push!(s.symbols, (v, loc, uri))
        elseif uri == s.current.uri
            push!(s.symbols, (Variable(Expr(:(.), x.defs[1].id, QuoteNode(v.id)), v.t, v.val), loc + offset2, s.current.uri))
        else
            push!(s.symbols, (Variable(Expr(:(.), x.defs[1].id, QuoteNode(v.id)), v.t, v.val), loc, uri))
        end
    end
end


"""
    findtopfile(uri::String, server, path = String[], namespace = [])

Checks for files that include `uri` then recursively finds the top of that 
tree returning the sequence of files - `path` - and any namespaces introduced - 
`namespace`.
"""
function findtopfile(uri::String, server, path = String[], namespace = [])
    follow = []
    for (uri1, doc1) in server.documents
        for (incl, ns) in doc1.code.includes
            if uri == incl
                append!(namespace, ns)
                push!(follow, uri1)
            end
        end
    end

    if isempty(follow)
        push!(path, uri)
        return path, namespace
    elseif length(follow) > 1
        for f in follow
            warn("$uri is included by more than one file, following the first: $f")
        end
        push!(path, uri)
        return findtopfile(first(follow), server, path, namespace)
    else
        push!(path, uri)
        return findtopfile(first(follow), server, path, namespace)
    end
end


function _find_scope(x::EXPR, s::Scope, server)
    if x.head == STRING
        return x
    elseif isimport(x)
        for d in x.defs
            unshift!(s.symbols, (d, s.current.offset + (1:x.span), s.current.uri))
        end
        return x
    elseif ismodule(x)
        push!(s.namespace, Expr(x.args[2]))
    end
    if s.current.offset + x.span < s.target.offset
        return NOTHING
    end
    push!(s.stack, x)
    for (i, a) in enumerate(x)
        if s.current.offset + a.span < s.target.offset
            get_scope(a, s, server)
            s.current.offset += a.span
        else
            if a isa EXPR
                for d in a.defs
                    push!(s.symbols, (d, s.current.offset + (1:a.span), s.current.uri))
                end
            end
            push!(s.stack_inds, i)
            push!(s.stack_offsets, s.current.offset)
            return _find_scope(a, s, server)
        end
    end
end
_find_scope(x, s::Scope, server) = x


function get_scope(x, s::Scope, server) end

function get_scope(x::EXPR, s::Scope, server)
    offset = s.current.offset
    for d in x.defs
        push!(s.symbols, (d, offset + (1:x.span), s.current.uri))
    end
    if contributes_scope(x)
        for a in x
            get_scope(a, s, server)
            offset += a.span
        end
    end

    if isinclude(x)
        get_include(x, s, server)
    end
end

