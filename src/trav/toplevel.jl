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
    imported_names::Dict{String,Set{String}}
    path::Vector{String}
end

function toplevel(doc, server, followincludes = true)
    s = TopLevelScope(ScopePosition("none", 0), ScopePosition(doc._uri, 0), false, Dict(), EXPR[], Symbol[], followincludes, true, Dict{String,Set{String}}("toplevel" => Set{String}()), [])

    toplevel(doc.code.ast, s, server)
    return s
end

function toplevel(x::EXPR, s::TopLevelScope, server)
    for a in x.args
        offset = s.current.offset
        toplevel_symbols(a, s, server)
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

function toplevel_symbols(x, s::TopLevelScope, server) end

function toplevel_symbols(x::EXPR, s::TopLevelScope, server)
    for v in get_defs(x)
        name = make_name(s.namespace, v.id)
        var_item = VariableLoc(v, s.current.offset + (0:x.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = VariableLoc[var_item]
        end
    end
end

function toplevel_symbols(x::EXPR{CSTParser.MacroCall}, s::TopLevelScope, server)
    if x.args[1].val == "@enum"
        offset = sum(x.args[i].fullspan for i = 1:3)
        enum_name = Symbol(x.args[3].val)
        v = Variable(enum_name, :Enum, x)
        name = make_name(s.namespace, enum_name)
        var_item = VariableLoc(v, s.current.offset + x.span, s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = VariableLoc[var_item]
        end
        for i = 4:length(x.args)
            a = x.args[i]
            if !(a isa EXPR{T} where T <: CSTParser.PUNCTUATION) && a isa EXPR{CSTParser.IDENTIFIER}
                v = Variable(a.val, enum_name, x)
                name = make_name(s.namespace, a.val)
                var_item = VariableLoc(v, offset + (1:a.fullspan), s.current.uri)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], var_item)
                else
                    s.symbols[name] = VariableLoc[var_item]
                end
            end
            offset += a.fullspan
        end
    end
end


function toplevel_symbols(x::EXPR{T}, s::TopLevelScope, server) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")
    if !haskey(s.imported_names, ns)
        s.imported_names[ns] = Set()
    end
    expr = Expr(x)
    import_modules(expr, server)
    get_imported_names(expr, s, server)
end

function import_modules(x::Expr, server)
    if x.head == :toplevel
        for a in x.args
            import_modules(a, server)
        end
    else
        if x.args[1] isa Symbol && x.args[1] != :. # julia issue 23173
            topmodname = x.args[1]
            if !isdefined(Main, topmodname)
                try 
                    @eval import $topmodname
                    server.loaded_modules[string(topmodname)] = load_mod_names(string(topmodname))
    
                    if isfile(Pkg.dir(string(topmodname)))
                        @async begin
                            watch_file(Pkg.dir(string(topmodname)))
                            info("reloading: $topmodname")
                            reload(string(topmodname))
                        end
                    end
                end
            elseif !(string(topmodname) in keys(server.loaded_modules))
                server.loaded_modules[string(topmodname)] = load_mod_names(string(topmodname))
            end
        end
    end
end

function load_mod_names(topmodname)
    load_mod_names(getfield(Main, Symbol(topmodname)))
end

function load_mod_names(mod::Module)
    expt_names = Set{String}()
    for name in names(mod)
        sname = string(name)
        if !startswith(sname, "#")
            push!(expt_names, sname)
        end
    end
    int_names = Set{String}()
    for name in names(mod, true, true)
        sname = string(name)
        if !startswith(sname, "#")
            push!(int_names, sname)
        end
    end

    expt_names, int_names
end

function get_defs(x::EXPR{CSTParser.Struct})
    [Variable(Expr(CSTParser.get_id(x.args[2])), :struct, x)]
end

function get_defs(x::EXPR{CSTParser.Mutable}) 
    if length(x.args) == 5
        [Variable(Expr(CSTParser.get_id(x.args[3])), Symbol("mutable struct"), x)]
    else # deprecated syntax
        [Variable(Expr(CSTParser.get_id(x.args[2])), Symbol("mutable struct"), x)]
    end
end

function get_defs(x::EXPR{CSTParser.Abstract})
    if length(x.args) == 4
        [Variable(Expr(CSTParser.get_id(x.args[3])), :abstract, x)]
    else
        [Variable(Expr(CSTParser.get_id(x.args[2])), :abstract, x)]
    end
end

function get_defs(x::EXPR{T}) where T <: Union{CSTParser.Primitive,CSTParser.Bitstype}
    [Variable(Expr(CSTParser.get_id(x.args[3])), :primitive, x)]
end


function get_defs(x) return Variable[] end

function get_defs(x::EXPR{CSTParser.ModuleH})
    [Variable(Expr(CSTParser.get_id(x.args[2])), :module, x)]
end

function get_defs(x::EXPR{CSTParser.BareModule})
    [Variable(string(Expr(CSTParser.get_id(x.args[2]))), :baremodule, x)]
end

function get_defs(x::EXPR{CSTParser.FunctionDef})
    [Variable(Expr(CSTParser._get_fname(x.args[2])), :function, x)]
end

function get_defs(x::EXPR{CSTParser.Macro})
    [Variable(Symbol("@", Expr(CSTParser._get_fname(x.args[2]))), :macro, x)]
end

function get_defs(x::EXPR{CSTParser.BinarySyntaxOpCall})
    if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}}
        if CSTParser.is_func_call(x.args[1])
            return Variable[Variable(Expr(CSTParser._get_fname(x.args[1])), :function, x)]
        elseif x.args[3] isa EXPR{CSTParser.BinarySyntaxOpCall} && x.args[3].args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}}
            defs = Variable[]
            val = x.args[3]
            while val isa EXPR{CSTParser.BinarySyntaxOpCall} && val.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}}
                val = val.args[3]
            end
            decl = x
            while decl isa EXPR{CSTParser.BinarySyntaxOpCall} && decl.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}}
                _track_assignment(decl.args[1], val, defs)
                decl = decl.args[3]
            end
            return defs
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

function get_imported_names(x::Expr, s, server)
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")
    if x.head == :toplevel
        for a in x.args
            get_imported_names(a, s, server)
        end
    elseif x.head == :using || x.head == :importall
        if x.args[1] == :.
        elseif length(x.args) == 1 && x.args[1] isa Symbol && string(x.args[1]) in keys(server.loaded_modules)
            union!(s.imported_names[ns], server.loaded_modules[string(x.args[1])][1])
        elseif length(x.args) > 1 && all(a -> a isa Symbol, x.args) && isdefined(Main, x.args[1])
            val = Main
            for i = 1:length(x.args)
                !isdefined(val, x.args[i]) && return
                val = getfield(val, x.args[i])
            end
            if val isa Module
                modname = join(x.args, ".")
                if !(modname in keys(server.loaded_modules))
                    server.loaded_modules[modname] = load_mod_names(val)
                end
                union!(s.imported_names[ns], server.loaded_modules[modname][1])
            else
                if isempty(s.namespace)
                    push!(s.imported_names[ns], string(x.args[1]))
                end
                push!(s.imported_names[ns], string(x.args[2]))
            end
        end
    elseif x.head == :import
        if x.args[1] == :.
        elseif length(x.args) == 2 && x.args[1] isa Symbol && x.args[1] in keys(server.loaded_modules) && string(x.args[2]) in server.loaded_modules[x.args[1]][2]
            push!(s.imported_names[ns], string(x.args[1]))
            push!(s.imported_names[ns], string(x.args[2]))
        else
            val = Main
            for i = 1:length(x.args)
                (!(x.args[i] isa Symbol) || !isdefined(val, x.args[i])) && return
                if i == 1
                    push!(s.imported_names[ns], string(x.args[1]))
                end
                val = getfield(val, x.args[i])
            end
            push!(s.imported_names[ns], string(x.args[end]))
        end
    end
end
