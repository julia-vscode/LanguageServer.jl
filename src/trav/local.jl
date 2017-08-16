function scope(doc::Document, offset::Int, server)
    uri = doc._uri

    # Find top file of include tree
    path, namespace = findtopfile(uri, server)
    
    s = TopLevelScope(ScopePosition(uri, offset), ScopePosition(last(path), 0), false, Dict(), EXPR[], Symbol[], true, true, Dict{String,Set{String}}("toplevel" => Set{String}()), [])
    toplevel(server.documents[last(path)].code.ast, s, server)
    

    s.current = ScopePosition(uri)
    s.namespace = namespace
    y = _scope(doc.code.ast, s, server)

    return y, s
end

_scope(x::EXPR{T}, s::TopLevelScope, server) where T <: Union{IDENTIFIER,Quotenode,LITERAL} = x
_scope(x::EXPR{CSTParser.KEYWORD{Tokens.END}}, s::TopLevelScope, server) = x
_scope(x::EXPR{CSTParser.PUNCTUATION{Tokens.RPAREN}}, s::TopLevelScope, server) = x
_scope(x::EXPR{CSTParser.PUNCTUATION{Tokens.LPAREN}}, s::TopLevelScope, server) = x
_scope(x::EXPR{CSTParser.PUNCTUATION{Tokens.COMMA}}, s::TopLevelScope, server) = x

function _scope(x::EXPR, s::TopLevelScope, server)
    if ismodule(x)
        toplevel_symbols(x, s, server)
        push!(s.namespace, x.args[2].val)
    end
    if s.current.offset + x.fullspan < s.target.offset
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
        elseif x isa EXPR{CSTParser.Do} && i == 2
            _do_scope(x, s, server)
        elseif x isa EXPR{CSTParser.BinarySyntaxOpCall} 
            if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AnonFuncOp,Tokens.ANON_FUNC,false}} && i == 1
                _anon_func_scope(x, s, server)
            elseif i == 1 && CSTParser.declares_function(x)
                _fsig_scope(a, s, server)
            end
        elseif x isa EXPR{CSTParser.Generator}
            _generator_scope(x, s, server)
        elseif x isa EXPR{CSTParser.Try} && i == 3
            _try_scope(x, s, server)
        end
        if s.current.offset + a.fullspan < s.target.offset
            !s.intoplevel && get_scope(a, s, server)
            s.current.offset += a.fullspan
        else
            if !s.intoplevel && a isa EXPR
                toplevel_symbols(a, s, server)
            end
            if !contributes_scope(a) && s.intoplevel
                s.intoplevel = false
            end
            return _scope(a, s, server)
        end
    end
end

# Add parameters and function arguments to the local scope
function _fsig_scope(sig1, s::TopLevelScope, server, loc = [])
    params = _get_fparams(sig1)
    for p in params
        name = make_name(s.namespace, p)
        var_item = (Variable(p, :DataType, sig1), s.current.offset + (0:sig1.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
        push!(loc, name)
    end
    sig = sig1
    while sig isa EXPR{CSTParser.BinarySyntaxOpCall} && (sig.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DeclarationOp,Tokens.DECLARATION,false}} || sig.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.WhereOp,Tokens.WHERE,false}})
        sig = sig.args[1]
    end
    for j = 2:length(sig.args)
        if sig.args[j] isa EXPR{CSTParser.Parameters}
            for parg in sig.args[j].args
                _add_sigarg(parg, sig, s, loc)
            end
        else
            _add_sigarg(sig.args[j], sig, s, loc)
        end
    end
end

function _add_sigarg(arg, sig, s, loc)
    if !(arg isa EXPR{P} where P <: CSTParser.PUNCTUATION)
        arg_id = CSTParser._arg_id(arg).val
        arg_t = CSTParser.get_t(arg)
        name = make_name(s.namespace, arg_id)
        var_item = (Variable(arg_id, arg_t, sig), s.current.offset + (0:sig.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
        push!(loc, name)
    end
end

function _for_scope(range, s::TopLevelScope, server, locals = []) end

function _for_scope(range::EXPR{T}, s::TopLevelScope, server, locals = []) where T <: Union{CSTParser.BinarySyntaxOpCall,CSTParser.BinaryOpCall}
    if range.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}} || range.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.ComparisonOp,Tokens.IN,false}} || range.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.ComparisonOp,Tokens.ELEMENT_OF,false}}
        defs = _track_assignment(range.args[1], range.args[3])
        for d in defs
            name = make_name(s.namespace, d.id)
            var_item = (d, s.current.offset + (0:range.fullspan), s.current.uri)
            if haskey(s.symbols, name)
                push!(s.symbols[name], var_item)
            else
                s.symbols[name] = [var_item]
            end
            push!(locals, name)
        end
    end
end

function _for_scope(range::EXPR{CSTParser.Block}, s::TopLevelScope, server, locals = [])
    for a in range.args
        _for_scope(a, s, server, locals)
    end
end

function _generator_scope(x::EXPR{CSTParser.Generator}, s::TopLevelScope, server, locals = [])
    offset = s.current.offset
    s.current.offset += sum(x.args[i].fullspan for i = 1:2)
    for i = 3:length(x.args)
        a = x.args[i]
        _for_scope(a, s, server, locals)
        s.current.offset += a.fullspan
    end
    s.current.offset = offset
end

function _try_scope(x::EXPR{CSTParser.Try}, s::TopLevelScope, server, locals = [])
    offset = s.current.offset
    if x.args[3] isa EXPR{CSTParser.KEYWORD{Tokens.CATCH}} && x.args[4].fullspan > 0
        s.current.offset += sum(x.args[i].fullspan for i = 1:3)
        
        d = Variable(x.args[4].val, :Any, x.args[4])
        name = make_name(s.namespace, d.id)
        var_item = (d, s.current.offset + x.args[1].fullspan + (0:x.args[2].fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
        push!(locals, name)
    end
    for i = 3:length(x.args)
        a = x.args[i]
        _for_scope(a, s, server)
        s.current.offset += a.fullspan
    end
    s.current.offset = offset
end

function _let_scope(x::EXPR{CSTParser.Let}, s::TopLevelScope, server, locals = [])
    for i = 2:length(x.args) - 2
        if x.args[i] isa EXPR{CSTParser.BinarySyntaxOpCall}
            defs = _track_assignment(x.args[i].args[1], x.args[i].args[3])
            for d in defs
                name = make_name(s.namespace, d.id)
                var_item = (d, s.current.offset + x.args[1].fullspan + (0:x.args[2].fullspan), s.current.uri)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], var_item)
                else
                    s.symbols[name] = [var_item]
                end
                push!(locals, name)
            end
        end
    end
end

function _anon_func_scope(x::EXPR{CSTParser.BinarySyntaxOpCall}, s::TopLevelScope, server, locals = [])
    if x.args[1] isa EXPR{CSTParser.TupleH}
        for a in x.args[1].args
            if !(a isa EXPR{T} where T <: CSTParser.PUNCTUATION)
                arg_id = CSTParser.get_id(a).val
                arg_t = CSTParser.get_t(x)
                name = make_name(s.namespace, arg_id)
                var_item = (Variable(arg_id, arg_t, x.args[1]), s.current.offset + (0:x.args[1].fullspan), s.current.uri)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], var_item)
                else
                    s.symbols[name] = [var_item]
                end
                push!(locals, name)
            end
        end
    else
        arg_id = CSTParser.get_id(x.args[1]).val
        arg_t = CSTParser.get_t(x.args[1])
        name = make_name(s.namespace, arg_id)
        var_item = (Variable(arg_id, arg_t, x.args[1]), s.current.offset + (0:x.args[1].fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
        push!(locals, name)
    end
end

function _do_scope(x::EXPR{CSTParser.Do}, s::TopLevelScope, server, locals = [])
    for i = 1:length(x.args[3].args)
        a = x.args[3].args[i]
        if !(a isa EXPR{T} where T <: CSTParser.PUNCTUATION)
            arg_id = CSTParser.get_id(a).val
            arg_t = CSTParser.get_t(a)
            name = make_name(s.namespace, arg_id)
            var_item = (Variable(arg_id, arg_t, x.args[1]), s.current.offset + x.args[1].fullspan + x.args[2].fullspan + (0:x.args[3].fullspan), s.current.uri)
            if haskey(s.symbols, name)
                push!(s.symbols[name], var_item)
            else
                s.symbols[name] = [var_item]
            end
            push!(locals, name)
        end
    end
end

function get_scope(x, s::TopLevelScope, server) end

function get_scope(x::EXPR, s::TopLevelScope, server)
    offset = s.current.offset
    toplevel_symbols(x, s, server)
    if contributes_scope(x)
        for a in x.args
            get_scope(a, s, server)
            s.current.offset += a.fullspan
        end
    end
    s.current.offset = offset

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

