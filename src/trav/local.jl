function scope(doc::Document, offset::Int, server)
    uri = doc._uri

    # Find top file of include tree
    path, namespace = findtopfile(uri, server)
 
    s = TopLevelScope(ScopePosition(uri, offset), ScopePosition(last(path), 0), false, Dict(), EXPR[], Symbol[], true, true, Dict{String,Set{String}}("toplevel" => Set{String}()), Dict{String,Set{String}}("toplevel" => Set{String}()), [])
    toplevel(server.documents[URI2(last(path))].code.ast, s, server)
 

    s.current = ScopePosition(uri)
    s.namespace = namespace
    y = _scope(doc.code.ast, s, server)

    return y, s
end

function scope(tdpp, server)
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character + 1)
    y, s = scope(doc, offset, server)
end


function _scope(x::T, s::TopLevelScope, server) where T <: Union{IDENTIFIER,Quotenode,LITERAL,KEYWORD,PUNCTUATION,OPERATOR}
    return x
end

function _scope(x, s::TopLevelScope, server)
    if ismodule(x)
        toplevel_symbols(x, s, server)
        push!(s.namespace, str_value(x.args[2]))
    end
    if s.current.offset + x.fullspan < s.target.offset
        return CSTParser.NOTHING
    end
    push!(s.stack, x)
    for (i, a) in enumerate(x)
        if (x isa EXPR{CSTParser.FunctionDef} || x isa EXPR{CSTParser.Macro}) && i == 2
            _fsig_scope(a, s, server)
        elseif x isa EXPR{CSTParser.For} && i == 2
            _for_scope(a, s, server)
        elseif x isa EXPR{CSTParser.Let} && i == 1
            _let_scope(x, s, server)
        elseif x isa EXPR{CSTParser.Do} && i == 2
            _do_scope(x, s, server)
        elseif x isa CSTParser.BinarySyntaxOpCall
            if CSTParser.is_anon_func(x.op) && i == 1
                _anon_func_scope(x, s, server)
            elseif i == 1 && CSTParser.defines_function(x)
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
            if !s.intoplevel
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
    params = CSTParser.get_sig_params(sig1)
    for p in params
        name = make_name(s.namespace, p)
        var_item = VariableLoc(Variable(p, :DataType, sig1), s.current.offset + (0:sig1.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = VariableLoc[var_item]
        end
        push!(loc, name)
    end
    sig = sig1
    while sig isa CSTParser.WhereOpCall || (sig isa CSTParser.BinarySyntaxOpCall && CSTParser.is_decl(sig.op))
        sig = sig.arg1
    end
    sig isa IDENTIFIER && return
    for (j, arg) = enumerate(sig)
        j == 1 && continue
        if arg isa EXPR{CSTParser.Parameters}
            for parg in arg.args
                _add_sigarg(parg, sig, s, loc)
            end
        else
            _add_sigarg(arg, sig, s, loc)
        end
    end
end

function _add_sigarg(arg, sig, s, loc)
    if !(arg isa PUNCTUATION)
        arg_id = str_value(CSTParser._arg_id(arg))
        isempty(arg_id) && return
        arg_t = CSTParser.get_t(arg)
        name = make_name(s.namespace, arg_id)
        var_item = VariableLoc(Variable(arg_id, arg_t, sig), s.current.offset + (0:sig.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = VariableLoc[var_item]
        end
        push!(loc, name)
    end
end

function _for_scope(range, s::TopLevelScope, server, locals = []) end

function _for_scope(range::T, s::TopLevelScope, server, locals = []) where T <: Union{CSTParser.BinarySyntaxOpCall,CSTParser.BinaryOpCall}
    if CSTParser.is_eq(range.op) || CSTParser.is_in(range.op) || CSTParser.is_elof(range.op)
        defs = _track_assignment(range.arg1, range.arg2)
        for d in defs
            name = make_name(s.namespace, d.id)
            var_item = VariableLoc(d, s.current.offset + (0:range.fullspan), s.current.uri)
            if haskey(s.symbols, name)
                push!(s.symbols[name], var_item)
            else
                s.symbols[name] = VariableLoc[var_item]
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
    if x.args[3] isa KEYWORD && x.args[3].kind == Tokens.CATCH && x.args[4].fullspan > 0
        s.current.offset += sum(x.args[i].fullspan for i = 1:3)
 
        d = Variable(str_value(x.args[4]), :Any, x.args[4])
        name = make_name(s.namespace, d.id)
        var_item = VariableLoc(d, s.current.offset + x.args[1].fullspan + (0:x.args[2].fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = VariableLoc[var_item]
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
        if x.args[i] isa CSTParser.BinarySyntaxOpCall
            defs = _track_assignment(x.args[i].arg1, x.args[i].arg2)
            for d in defs
                name = make_name(s.namespace, d.id)
                var_item = VariableLoc(d, s.current.offset + x.args[1].fullspan + (0:x.args[2].fullspan), s.current.uri)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], var_item)
                else
                    s.symbols[name] = VariableLoc[var_item]
                end
                push!(locals, name)
            end
        end
    end
end

function _anon_func_scope(x::CSTParser.BinarySyntaxOpCall, s::TopLevelScope, server, locals = [])
    if x.arg1 isa EXPR{CSTParser.TupleH}
        for a in x.arg1.args
            if !(a isa PUNCTUATION)
                arg_id = str_value(CSTParser.get_id(a))
                arg_t = CSTParser.get_t(x)
                name = make_name(s.namespace, arg_id)
                var_item = VariableLoc(Variable(arg_id, arg_t, x.arg1), s.current.offset + (0:x.arg1.fullspan), s.current.uri)
                if haskey(s.symbols, name)
                    push!(s.symbols[name], var_item)
                else
                    s.symbols[name] = VariableLoc[var_item]
                end
                push!(locals, name)
            end
        end
    else
        arg_id = str_value(CSTParser.get_id(x.arg1))
        arg_t = CSTParser.get_t(x.arg1)
        name = make_name(s.namespace, arg_id)
        var_item = VariableLoc(Variable(arg_id, arg_t, x.arg1), s.current.offset + (0:x.arg1.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = VariableLoc[var_item]
        end
        push!(locals, name)
    end
end

function _do_scope(x::EXPR{CSTParser.Do}, s::TopLevelScope, server, locals = [])
    for i = 1:length(x.args[3].args)
        a = x.args[3].args[i]
        if !(a isa PUNCTUATION)
            arg_id = str_value(CSTParser.get_id(a))
            arg_t = CSTParser.get_t(a)
            name = make_name(s.namespace, arg_id)
            var_item = VariableLoc(Variable(arg_id, arg_t, x.args[1]), s.current.offset + x.args[1].fullspan + x.args[2].fullspan + (0:x.args[3].fullspan), s.current.uri)
            if haskey(s.symbols, name)
                push!(s.symbols[name], var_item)
            else
                s.symbols[name] = VariableLoc[var_item]
            end
            push!(locals, name)
        end
    end
end


function get_scope(x, s::TopLevelScope, server)
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
        file = isabspath(file) ? filepath2uri(file) : joinuriwithpath(dirname(s.current.uri), file)
 
        file in s.path && return
 
        if haskey(server.documents, URI2(file))
            oldpos = s.current
            s.current = ScopePosition(file, 0)
            incl_syms = toplevel(server.documents[URI2(file)].code.ast, s, server)
            s.current = oldpos
        end
    end
end

