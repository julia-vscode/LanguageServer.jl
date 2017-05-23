import CSTParser: IDENTIFIER, INSTANCE, Quotenode, LITERAL, EXPR, ERROR, KEYWORD, HEAD, Tokens, Variable
import CSTParser: TopLevel, String, Block, Call, NOTHING, FileH
import CSTParser: contributes_scope

mutable struct ScopePosition
    uri::String
    offset::Int
    ScopePosition(uri = "",  offset = 0) = new(uri, offset)
end

mutable struct Scope
    target::ScopePosition
    current::ScopePosition
    symbols::Vector{VariableLoc}
    stack::Vector{CSTParser.EXPR}
    stack_inds::Vector{Int}
    stack_offsets::Vector{Int}
    namespace::Vector
    hittarget::Bool
    followincludes::Bool
    intoplevel::Bool
end
Scope(uri::String, followincludes = true) = Scope(ScopePosition(), ScopePosition(uri, 0), [], [], [], [], [], false, followincludes, true)


function get_scope(doc::Document, offset::Int, server)
    uri = doc._uri

    # Find top file of include tree
    path, namespace = findtopfile(uri, server)
    
    s = Scope(ScopePosition(uri, offset), ScopePosition(last(path), 0), [], [], [], [], namespace, false, true, true)
    get_toplevel(server.documents[last(path)].code.ast, s, server)
    

    s.current = ScopePosition(uri)
    y = _find_scope(doc.code.ast, s, server)

    current_namespace = isempty(s.namespace) ? :NOTHING : repack_dot(s.namespace)
    modules = collect_imports(s.symbols, server)

    return y, s, modules, current_namespace
end



function collect_imports(S::Vector{VariableLoc}, server)
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




"""
    get_toplevel(x::EXPR, s::Scope, server)

Collects declared variables within an expression, stops if a target 
specified in `s` is met, will optionally follow includes.
"""
function get_toplevel(doc::Document, server, followincludes = true)
    s = Scope(doc._uri, followincludes)
    get_toplevel(doc.code.ast, s, server)
    return s
end

function get_toplevel(x::EXPR, s::Scope, server)
    if isimport(x)
        get_imports(x, s)
        return
    end
    for a in x.args
        offset = s.current.offset
        if s.hittarget
            return
        elseif (s.current.uri == s.target.uri && s.current.offset <= s.target.offset <= (s.current.offset + a.span)) && !(CSTParser.contributes_scope(a) || ismodule(a) || CSTParser.declares_function(a))
            s.hittarget = true 
            return
        end
        if s.followincludes && isincludable(a)
            follow_include(a, s, server)
        end
        get_symbols(a, s)

        if ismodule(a)
            get_module(a, s, server)
        elseif contributes_scope(a)
            get_toplevel(a, s, server)
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

function get_imports(x::EXPR, s::Scope)
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
    s_module = Scope(s.target, ScopePosition(s.current.uri, s.current.offset + x.args[1].span + x.args[2].span), [], [], [], [], [], s.hittarget, s.followincludes, s.intoplevel)
    get_toplevel(x.args[3], s_module, server)
    offset2 = s.current.offset + x.args[1].span + x.args[2].span
    for (v, loc, uri) in s_module.symbols
        if v.t == :IMPORTS
            push!(s.symbols, (v, loc, uri))
        # elseif uri == s.current.uri
        #     push!(s.symbols, (Variable(Expr(:(.), x.defs[1].id, QuoteNode(v.id)), v.t, v.val), loc + offset2, s.current.uri))
        else
            push!(s.symbols, (Variable(Expr(:(.), x.defs[1].id, QuoteNode(v.id)), v.t, v.val), loc, uri))
        end
    end
end

_find_scope(x::EXPR{IDENTIFIER}, s::Scope, server) = x
_find_scope(x::EXPR{CSTParser.Quotenode}, s::Scope, server) = x
_find_scope(x::EXPR{L}, s::Scope, server) where L <: CSTParser.LITERAL = x


function _find_scope(x::EXPR, s::Scope, server)
    if isimport(x)
        !s.intoplevel && get_imports(x, s)
        return x
    elseif ismodule(x)
        push!(s.namespace, Expr(x.args[2]))
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
                get_symbols(a, s)
            end
            push!(s.stack_inds, i)
            push!(s.stack_offsets, s.current.offset)
            if !contributes_scope(a) && s.intoplevel
                s.intoplevel = false
            end
            return _find_scope(a, s, server)
        end
    end
end



function get_scope(x, s::Scope, server) end

function get_scope(x::EXPR, s::Scope, server)
    offset = s.current.offset
    for d in x.defs
        push!(s.symbols, (d, offset + (1:x.span), s.current.uri))
    end
    if contributes_scope(x)
        for a in x.args
            get_scope(a, s, server)
            offset += a.span
        end
    end

    if isincludable(x)
        follow_include(x, s, server)
    end
end


"""
    isincludable(x)
Checks whether `x` is an expression that includes a file.
"""
isincludable(x) = false
function isincludable(x::EXPR{Call})
    x.args[1] isa EXPR{IDENTIFIER} && x.args[1].val == "include" && length(x.args) == 4 && (x.args[3] isa EXPR{LITERAL{Tokens.STRING}} || x.args[3] isa EXPR{LITERAL{Tokens.TRIPLE_STRING}})
end

"""
    isimport(x)
Checks whether `x` is an expression that imports a module.
"""
isimport(x) = false
isimport(x::EXPR{CSTParser.Import}) = true
isimport(x::EXPR{CSTParser.ImportAll}) = true
isimport(x::EXPR{CSTParser.Using}) = true

"""
    ismodule(x)
Checks whether `x` is an expression that declares a module.
"""
ismodule(x) = false
ismodule(x::EXPR{CSTParser.ModuleH}) = true
ismodule(x::EXPR{CSTParser.BareModule}) = true



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

"""
    follow_include(x, s, server)

Adds the contents of a file (in the workspace) to the current scope.
"""
function follow_include(x::EXPR{Call}, s::Scope, server)
    file = Expr(x.args[3])
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

function _get_includes(x, files = []) end
function _get_includes(x::EXPR{Call}, files = [])
    if isincludable(x)
        push!(files, (x.args[3].val, []))
    end
    return files
end


function _get_includes(x::EXPR, files = [])
    for a in x.args
        if a isa EXPR{CSTParser.ModuleH} || a isa EXPR{CSTParser.BareModule}
            mname = Expr(a.args[2])
            files1 = _get_includes(a)
            for (f, ns) in files1
                push!(files, (f, vcat(mname, ns)))
            end
        elseif !(x isa EXPR{Call})
            _get_includes(a, files)
        end
    end
    return files
end
