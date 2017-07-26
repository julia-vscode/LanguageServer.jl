import CSTParser: IDENTIFIER, INSTANCE, Quotenode, LITERAL, EXPR, ERROR, KEYWORD, HEAD, Tokens, Variable
import CSTParser: TopLevel, Block, Call, NOTHING, FileH
import CSTParser: contributes_scope

mutable struct ScopePosition
    uri::String
    offset::Int
    ScopePosition(uri = "",  offset = 0) = new(uri, offset)
end


mutable struct TopLevelScope
    target::ScopePosition
    current::ScopePosition
    hittarget::Bool
    symbols::Dict{String,Vector{VariableLoc}}
    stack::Vector{EXPR}
    namespace::Vector{Symbol}
    followincludes::Bool
    intoplevel::Bool
    imports::Dict{String,Vector{Tuple{Expr,UnitRange{Int},String}}}
    path::Vector{String}
end

function toplevel(doc, server, followincludes = true)
    s = TopLevelScope(ScopePosition("none", 0), ScopePosition(doc._uri, 0), false, Dict(), EXPR[], Symbol[], followincludes, true, Dict(:toplevel => []), [])

    toplevel(doc.code.ast, s, server)
    return s
end

function toplevel(x::EXPR, s::TopLevelScope, server)
    for a in x.args
        offset = s.current.offset
        if s.hittarget || ((s.current.uri == s.target.uri && s.current.offset <= s.target.offset <= (s.current.offset + a.span)) && !(CSTParser.contributes_scope(a) || ismodule(a) || CSTParser.declares_function(a)))
            s.hittarget = true 
            return
        end
        toplevel_symbols(a, s)

        if ismodule(a)
            push!(s.namespace, a.defs[1].id)
            toplevel(a, s, server)
            pop!(s.namespace)
        elseif contributes_scope(a)
            toplevel(a, s, server)
        elseif s.followincludes && isincludable(a)
            file = Expr(a.args[3])
            file = isabspath(file) ? filepath2uri(file) : joinpath(dirname(s.current.uri), normpath(file))

            file in s.path && return

            if file in keys(server.documents)
                push!(s.path, file)
                oldpos = s.current
                s.current = ScopePosition(file, 0)
                incl_syms = toplevel(server.documents[file].code.ast, s, server)
                s.current = oldpos
            end
        end
        s.current.offset = offset + a.span
    end
    return 
end

function toplevel_symbols(x, s::TopLevelScope) end
function toplevel_symbols(x::EXPR, s::TopLevelScope)
    for v in x.defs
        name = make_name(s.namespace, v.id)
        var_item = (v, s.current.offset + (0:x.span), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
    end
end


function toplevel_symbols(x::EXPR{T}, s::TopLevelScope) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    if isempty(s.namespace)
        ns = "toplevel"
    else
        ns = join(s.namespace, ".")
    end
    if !haskey(s.imports, ns)
        s.imports[ns] = []
    end
    for d in x.defs
        if d.id.head == :toplevel
            for a in d.id.args
                push!(s.imports[ns], (a, sum(s.current.offset) + (0:x.span), s.current.uri))
            end
        else
            if all(i -> i isa Symbol, d.id.args)
                push!(s.imports[ns], (d.id, sum(s.current.offset) + (0:x.span), s.current.uri))
            end
        end
    end
end
