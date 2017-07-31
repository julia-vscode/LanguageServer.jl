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
        push!(s.namespace, x.args[2].val)
    end
    if s.current.offset + x.span < s.target.offset
        return NOTHING
    end
    push!(s.stack, x)
    for (i, a) in enumerate(x.args)
        if (x isa EXPR{CSTParser.FunctionDef} || x isa EXPR{CSTParser.Macro}) && i == 2
            _fsig_scope(a, s, server)
        elseif x isa EXPR{CSTParser.For} && i == 2
            _for_scope(a, s, server)
        elseif x isa EXPR{CSTParser.Let} && i == 1
            _let_scope(x, s, server)
        elseif x isa EXPR{CSTParser.BinarySyntaxOpCall} && x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AnonFuncOp,Tokens.ANON_FUNC,false}} && i == 1
            _anon_func_scope(x, s, server)
        end
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

# Add parameters and function arguments to the local scope
function _fsig_scope(sig1, s::TopLevelScope, server)
    params = CSTParser._get_fparams(sig1)
    for p in params
        name = make_name(s.namespace, p)
        var_item = (Variable(p, :DataType, sig1), s.current.offset + (0:sig1.span), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
    end
    sig = sig1
    while sig isa EXPR{CSTParser.BinarySyntaxOpCall} && (sig.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DeclarationOp,Tokens.DECLARATION,false}} || sig.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.WhereOp,Tokens.WHERE,false}})
        sig = sig.args[1]
    end
    for j = 2:length(sig.args)
        if !(sig.args[j] isa EXPR{P} where P <: CSTParser.PUNCTUATION)
            arg_id = CSTParser.get_id(sig.args[j]).val
            arg_t = CSTParser.get_t(sig.args[j])
            name = make_name(s.namespace, arg_id)
            var_item = (Variable(arg_id, arg_t, sig1), s.current.offset + (0:sig.span), s.current.uri)
            if haskey(s.symbols, name)
                push!(s.symbols[name], var_item)
            else
                s.symbols[name] = [var_item]
            end
        end
    end
end

function _for_scope(range, s::TopLevelScope, server) end

function _for_scope(range::EXPR{T}, s::TopLevelScope, server) where T <: Union{CSTParser.BinarySyntaxOpCall,CSTParser.BinaryOpCall}
    if range.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}} || range.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.ComparisonOp,Tokens.IN,false}} || range.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.ComparisonOp,Tokens.ELEMENT_OF,false}}
        defs = _track_assignment(range.args[1], range.args[3])
        for d in defs
            name = make_name(s.namespace, d.id)
            var_item = (d, s.current.offset + (0:range.span), s.current.uri)
            if haskey(s.symbols, name)
                push!(s.symbols[name], var_item)
            else
                s.symbols[name] = [var_item]
            end
        end
    end
end

function _for_scope(range::EXPR{CSTParser.Block}, s::TopLevelScope, server)
    for a in range.args
        _for_scope(a, s, server)
    end
end

function _let_scope(x::EXPR{CSTParser.Let}, s::TopLevelScope, server)
    for i = 2:length(x.args) - 2
        if x.args[i] isa EXPR{CSTParser.BinarySyntaxOpCall}
            defs = _track_assignment(x.args[i].args[1], x.args[i].args[3])
            for d in defs
                name = make_name(s.namespace, d.id)
                var_item = (d, s.current.offset + x.args[1].span + (0:x.args[2].span), s.current.uri)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], var_item)
                else
                    s.symbols[name] = [var_item]
                end
            end
        end
    end
end

function _anon_func_scope(x::EXPR{CSTParser.BinarySyntaxOpCall}, s::TopLevelScope, server)
    if x.args[1] isa EXPR{CSTParser.TupleH}
        for a in x.args[1].args
            if !(a isa EXPR{T} where T <: CSTParser.PUNCTUATION)
                arg_id = CSTParser.get_id(a).val
                arg_t = CSTParser.get_t(x)
                name = make_name(s.namespace, arg_id)
                var_item = (Variable(arg_id, arg_t, x.args[1]), s.current.offset + (0:x.args[1].span), s.current.uri)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], var_item)
                else
                    s.symbols[name] = [var_item]
                end
            end
        end
    else
        arg_id = CSTParser.get_id(x.args[1]).val
        arg_t = CSTParser.get_t(x.args[1])
        name = make_name(s.namespace, arg_id)
        var_item = (Variable(arg_id, arg_t, x.args[1]), s.current.offset + (0:x.args[1].span), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
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

