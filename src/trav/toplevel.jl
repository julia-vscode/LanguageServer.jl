import CSTParser: IDENTIFIER, INSTANCE, Quotenode, LITERAL, EXPR, ERROR, KEYWORD, Tokens
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
        toplevel_symbols(a, s)
        if s.hittarget || ((s.current.uri == s.target.uri && s.current.offset <= s.target.offset <= (s.current.offset + a.fullspan)) && !(CSTParser.contributes_scope(a) || ismodule(a) || CSTParser.declares_function(a)))
            s.hittarget = true 
            return
        end

        if ismodule(a)
            push!(s.namespace, a.args[2].val)
            toplevel(a, s, server)
            pop!(s.namespace)
        elseif contributes_scope(a)
            toplevel(a, s, server)
        elseif s.followincludes && isincludable(a)
            file = Expr(a.args[3])
            uri = isabspath(file) ? filepath2uri(file) : joinpath(dirname(s.current.uri), normpath(file))

            uri in s.path && return
            if uri in keys(server.documents)
                push!(s.path, uri)
                oldpos = s.current
                s.current = ScopePosition(uri, 0)
                incl_syms = toplevel(server.documents[uri].code.ast, s, server)
                s.current = oldpos
            end
        end
        s.current.offset = offset + a.fullspan
    end
    return 
end

function toplevel_symbols(x, s::TopLevelScope) end

function toplevel_symbols(x::EXPR, s::TopLevelScope)
    for v in get_defs(x)
        name = make_name(s.namespace, v.id)
        var_item = (v, s.current.offset + (0:x.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
    end
end

function toplevel_symbols(x::EXPR{CSTParser.MacroCall}, s::TopLevelScope)
    if x.args[1].val == "@enum"
        offset = sum(x.args[i].fullspan for i = 1:3)
        enum_name = Symbol(x.args[3].val)
        v = Variable(enum_name, :Enum, x)
        name = make_name(s.namespace, enum_name)
        if haskey(s.symbols, name)
            push!(s.symbols[name], (v, s.current.offset + x.span, s.current.uri))
        else
            s.symbols[name] = [(v, s.current.offset + x.span, s.current.uri)]
        end
        for i = 4:length(x.args)
            a = x.args[i]
            if !(a isa EXPR{T} where T <: CSTParser.PUNCTUATION) && a isa EXPR{CSTParser.IDENTIFIER}
                v = Variable(a.val, enum_name, x)
                name = make_name(s.namespace, a.val)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], (v, offset + (1:a.fullspan), s.current.uri))
                else
                    s.symbols[name] = [(v, offset + (1:a.fullspan), s.current.uri)]
                end
            end
            offset += a.fullspan
        end
    end
end


function toplevel_symbols(x::EXPR{T}, s::TopLevelScope) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")
    
    if !haskey(s.imports, ns)
        s.imports[ns] = []
    end
    if x.args[2] isa EXPR{CSTParser.IDENTIFIER}
        topmodname = Expr(x.args[2])
        if !isdefined(Main, topmodname)
            try 
                @eval import $topmodname 
                if isfile(Pkg.dir(string(topmodname)))
                    @async begin
                        watch_file(Pkg.dir(string(topmodname)))
                        info("reloading: $topmodname")
                        reload(string(topmodname))
                    end
                end
            end
        end
    end
    expr = Expr(x)
    if expr.head != :toplevel
        expr = Expr(:toplevel, expr)
    end
    for a in expr.args
        push!(s.imports[ns], (a, sum(s.current.offset) + (0:x.fullspan), s.current.uri))
    end
end



function get_defs(x::EXPR{CSTParser.Struct})
    [Variable(string(Expr(CSTParser.get_id(x.args[2]))), :mutable, x)]
end

function get_defs(x::EXPR{CSTParser.Mutable}) 
    [Variable(string(Expr(CSTParser.get_id(x.args[3]))), :mutable, x)]
end

function get_defs(x::EXPR{CSTParser.Abstract})
    if length(x.args) == 4
        [Variable(string(Expr(CSTParser.get_id(x.args[3]))), :abstract, x)]
    else
        [Variable(string(Expr(CSTParser.get_id(x.args[2]))), :abstract, x)]
    end
end

function get_defs(x::EXPR{CSTParser.Primitive})
    [Variable(string(Expr(CSTParser.get_id(x.args[3]))), :primitive, x)]
end

function get_defs(x) return Variable[] end

function get_defs(x::EXPR{CSTParser.ModuleH})
    [Variable(string(Expr(CSTParser.get_id(x.args[2]))), :module, x)]
end

function get_defs(x::EXPR{CSTParser.BareModule})
    [Variable(string(Expr(CSTParser.get_id(x.args[2]))), :baremodule, x)]
end

function get_defs(x::EXPR{CSTParser.FunctionDef})
    [Variable(string(Expr(CSTParser._get_fname(x.args[2]))), :function, x)]
end

function get_defs(x::EXPR{CSTParser.Macro})
    [Variable(string("@", Expr(CSTParser._get_fname(x.args[2]))), :macro, x)]
end

function get_defs(x::EXPR{CSTParser.BinarySyntaxOpCall})
    if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}}
        if CSTParser.is_func_call(x.args[1])
            return Variable[Variable(string(Expr(CSTParser._get_fname(x.args[1]))), :function, x)]
        else
            return _track_assignment(x.args[1], x.args[3])
        end
    else
        return Variable[]
    end
end

"""
_track_assignment(x, val, defs = [])

When applied to the lhs of an assignment returns a vector of the 
newly defined variables.
"""
function _track_assignment(x, val, defs::Vector{Variable} = Variable[])
    return defs::Vector{Variable}
end

function _track_assignment(x::EXPR{CSTParser.IDENTIFIER}, val, defs::Vector{Variable} = Variable[])
    t = CSTParser.infer_t(val)
    push!(defs, Variable(Expr(x), t, val))
    return defs
end

function _track_assignment(x::EXPR{CSTParser.BinarySyntaxOpCall}, val, defs::Vector{Variable} = Variable[])
    if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DeclarationOp,Tokens.DECLARATION,false}}
        t = Expr(x.args[3])
        push!(defs, Variable(Expr(CSTParser.get_id(x.args[1])), t, val))
    end
    return defs
end

function _track_assignment(x::EXPR{CSTParser.Curly}, val, defs::Vector{Variable} = Variable[])
    t = CSTParser.infer_t(val)
    push!(defs, Variable(Expr(CSTParser.get_id(x)), t, val))
    return defs
end

function _track_assignment(x::EXPR{CSTParser.TupleH}, val, defs::Vector{Variable} = Variable[])
    for a in x.args
        _track_assignment(a, val, defs)
    end
    return defs
end
