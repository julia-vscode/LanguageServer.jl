mutable struct LintState
    istop::Bool
    ns::Vector{Union{Symbol,EXPR}}
    diagnostics::Vector{CSTParser.Diagnostics.Diagnostic}
    locals::Vector{Set{String}}
end

function lint(doc::Document, server)
    uri = doc._uri
    tic()
    # Find top file of include tree
    path, namespace = findtopfile(uri, server)
    
    s = TopLevelScope(ScopePosition(uri, typemax(Int)), ScopePosition(last(path), 0), false, Dict(), EXPR[], Symbol[], true, true, Dict("toplevel" => []))
    toplevel(server.documents[last(path)].code.ast, s, server)

    current_namespace = isempty(s.namespace) ? "toplevel" : join(reverse(s.namespace), ".")
    
    s.current = ScopePosition(uri)
    s.namespace = namespace

    L = LintState(true, reverse(namespace), [], [])
    lint(doc.code.ast, s, L, server, true)
    server.debug_mode && info("LINTING: $(toq())")
    return L
end

function lint(x::EXPR, s::TopLevelScope, L::LintState, server, istop) 
    for a in x.args
        offset = s.current.offset
        if istop
        else
            get_symbols(a, s, L)
        end

        if contributes_scope(a)
            lint(a, s, L, server, istop)
        else
            if ismodule(a)
                push!(s.namespace, a.defs[1].id)
            end
            # Add new local scope
            if !(a isa EXPR{IDENTIFIER})
                push!(L.locals, Set{String}())
            end
            lint(a, s, L, server, ismodule(a))
            
            # Delete local scope
            if !(a isa EXPR{IDENTIFIER})
                for k in pop!(L.locals)
                    remove_symbol(s.symbols, k)
                end
            end
            if ismodule(a)
                pop!(s.namespace)
            end
        end
        s.current.offset = offset + a.span
    end
    return
end

function lint(x::EXPR{IDENTIFIER}, s::TopLevelScope, L::LintState, server, istop)
    Ex = Symbol(x.val)
    nsEx = make_name(s.namespace, x.val)
    found = Ex in BaseCoreNames

    if !found
        if haskey(s.symbols, x.val)
            found = true
        end
    end
    if !found
        if haskey(s.symbols, nsEx)
            found = true
        end
    end
    
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")

    if !found && haskey(s.imports, ns)
        for (impt, loc, uri) in s.imports[ns]
            if length(impt.args) == 1
                if Ex == impt.args[1]
                    found = true
                    break
                else
                    if isdefined(Main, impt.args[1]) && getfield(Main, impt.args[1]) isa Module && Ex in names(getfield(Main, impt.args[1]))
                        found = true
                        break
                    end
                end
            else
                if Ex == impt.args[end]
                    found = true
                    break
                end
            end
        end
    end
    if !found
        loc = s.current.offset + (0:sizeof(x.val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Possible use of undeclared variable $(x.val)"))
    end
end

function lint(x::EXPR{CSTParser.ModuleH}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].span + x.args[2].span
    lint(x.args[3], s, L, server, istop)
end

# function lint(x::EXPR{CSTParser.Call}, s::TopLevelScope, L::LintState, server, istop)
#     if x.args[1] isa EXPR{IDENTIFIER}
#         nsEx = make_name(s.namespace, x.args[1].val)
#         if haskey(s.symbols, nsEx) && !(last(s.symbols[nsEx])[1].t == :Function || last(s.symbols[nsEx])[1].t == :immutable || last(s.symbols[nsEx])[1].t == :mutable)
#             loc = s.current.offset + (0:sizeof(x.args[1].val))
#             push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "$(x.val) is not callable"))
#         end
#     end
#     invoke(lint, Tuple{EXPR,TopLevelScope,LintState,Any,Any}, x, s, L, server, istop)
# end

function lint(x::EXPR{CSTParser.Kw}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].span + x.args[2].span
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Generator}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].span + x.args[2].span
    for i = 3:length(x.args)
        r = x.args[i]
        for v in r.defs
            name = make_name(s.namespace, v.id)
            if haskey(s.symbols, name)
                push!(s.symbols[name], (v, s.current.offset + (1:r.span), s.current.uri))
            else
                s.symbols[name] = [(v, s.current.offset + (1:r.span), s.current.uri)]
            end
            push!(last(L.locals), name)
        end
        offset += r.span
    end
    lint(x.args[1], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Quotenode}, s::TopLevelScope, L::LintState, server, istop)
end

function lint(x::EXPR{CSTParser.Quote}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: traverse args only linting -> x isa EXPR{UnarySyntaxOpCall} && x.args[1] isa EXPR{OP} where OP <: CSTParser.OPERATOR{CSTParser.PlusOp, Tokens.EX_OR}
end


# Types
function lint(x::EXPR{CSTParser.Mutable}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa EXPR{CSTParser.KEYWORD{Tokens.TYPE}}
        push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.typeDeprecation}(s.current.offset + (0:4), [CSTParser.Diagnostics.TextEdit(s.current.offset + (0:x.args[1].span), "mutable struct ")], "Use of deprecated `type` syntax"))

        name = CSTParser.get_id(x.args[2])
        nsEx = make_name(s.namespace, name.val)
        if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx])[2]) == s.current.offset)
            loc = s.current.offset + x.args[1].span + (0:sizeof(name.val))
            push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Cannot declare $(x.val) constant, it already has a value"))
        end
        offset = s.current.offset + x.args[1].span + x.args[2].span
        for a in x.args[3].args
            if CSTParser.declares_function(a)
                fname = CSTParser._get_fname(CSTParser._get_fsig(a))
                if fname.val != name.val
                    push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.MisnamedConstructor}(offset + (0:a.span), [], "Constructor name does not match type name"))
                end
            end
            offset += a.span
        end
    else
        name = CSTParser.get_id(x.args[3])
        nsEx = make_name(s.namespace, name.val)
        if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx])[2]) == s.current.offset)
            loc = s.current.offset + x.args[1].span + x.args[2].span + (0:sizeof(name.val))
            push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Cannot declare $(x.val) constant, it already has a value"))
        end
        offset = s.current.offset + x.args[1].span + x.args[2].span + x.args[3].span
        for a in x.args[4].args
            if CSTParser.declares_function(a)
                fname = CSTParser._get_fname(CSTParser._get_fsig(a))
                if fname.val != name.val
                    push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.MisnamedConstructor}(offset + (0:a.span), [], "Constructor name does not match type name"))
                end
            end
            offset += a.span
        end
    end
end

function lint(x::EXPR{CSTParser.Struct}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa EXPR{CSTParser.KEYWORD{Tokens.IMMUTABLE}}
        push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.immutableDeprecation}(s.current.offset + (0:9), [CSTParser.Diagnostics.TextEdit(s.current.offset + (0:x.args[1].span), "struct ")], "Use of deprecated `immutable` syntax"))
    end
    name = CSTParser.get_id(x.args[2])
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + x.args[1].span + (0:sizeof(name.val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Cannot declare $(x.val) constant, it already has a value"))
    end
    offset = s.current.offset + x.args[1].span + x.args[2].span
    for a in x.args[3].args
        if CSTParser.declares_function(a)
            fname = CSTParser._get_fname(CSTParser._get_fsig(a))
            if fname.val != name.val
                push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.MisnamedConstructor}(offset + (0:a.span), [], "Constructor name does not match type name"))
            end
        end
        offset += a.span
    end
end

function lint(x::EXPR{CSTParser.Abstract}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: allow use of undeclared parameters
    if length(x.args) == 2 # deprecated syntax
        offset = x.args[1].span
        l_pos = s.current.offset + x.span - trailing_ws_length(get_last_token(x))
        decl = x.args[2]
        push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.abstractDeprecation}(s.current.offset + (0:8), [CSTParser.Diagnostics.TextEdit(l_pos:l_pos, " end"), CSTParser.Diagnostics.TextEdit(s.current.offset + (0:offset), "abstract type ")], "This specification for abstract types is deprecated"))
    else
        offset = x.args[1].span + x.args[2].span
        decl = x.args[3]
    end
    name = CSTParser.get_id(decl)
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(length(s.symbols[nsEx]) == 1 && first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + offset + (0:sizeof(name.val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Cannot declare $(x.val) constant, it already has a value"))
    end
end

function lint(x::EXPR{CSTParser.Bitstype}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].span + x.args[2].span
    
    push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.bitstypeDeprecation}(s.current.offset + (0:8), [CSTParser.Diagnostics.TextEdit(s.current.offset + (0:(x.span)), string("primitive type ", Expr(x.args[3])," ", Expr(x.args[2]), " end"))], "This specification for primitive types is deprecated"))
    
    name = CSTParser.get_id(x.args[3])
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(length(s.symbols[nsEx]) == 1 && first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + offset + (0:sizeof(name.val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Cannot declare $(x.val) constant, it already has a value"))
    end

    if x.args[2] isa EXPR{CSTParser.LITERAL{Tokens.INTEGER}} && mod(Expr(x.args[2]), 8) != 0
        loc = s.current.offset + x.args[1].span + (0:sizeof(x.args[2].val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Invalid number of bits in primitive type $(name.val)"))
    end
end

function lint(x::EXPR{CSTParser.Primitive}, s::TopLevelScope, L::LintState, server, istop)
    name = CSTParser.get_id(x.args[3])
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(length(s.symbols[nsEx]) == 1 && first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + x.args[1].span + x.args[2].span + (0:sizeof(name.val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Cannot declare $(x.val) constant, it already has a value"))
    end

    if x.args[4] isa EXPR{CSTParser.LITERAL{Tokens.INTEGER}} && mod(Expr(x.args[4]), 8) != 0
        loc = s.current.offset + x.args[1].span + x.args[2].span + x.args[3].span + (0:sizeof(x.args[4].val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Invalid number of bits in primitive type $(name.val)"))
    end
end

function lint(x::EXPR{CSTParser.TypeAlias}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].span
    lt = CSTParser.get_last_token(x)
    tws = CSTParser.trailing_ws_length(lt)
    push!(L.diagnostics, CSTParser.Diagnostic{CSTParser.Diagnostics.typealiasDeprecation}(s.current.offset + (0:9), [CSTParser.Diagnostics.TextEdit(s.current.offset + (0:(x.span - tws)), string("const ", Expr(x.args[2]), " = ", Expr(x.args[3])))], "This specification for type aliases is deprecated"))
end

function lint(x::EXPR{CSTParser.Macro}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].span + x.args[2].span
    get_symbols(x.args[2], s, L)
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.x_Str}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].span
    lint(x.args[2], s, L, server, istop)
end


function lint(x::EXPR{CSTParser.Const}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: skip if declaring parameterised type alias
    if x.args[2] isa EXPR{CSTParser.BinarySyntaxOpCall} && x.args[2].args[1] isa EXPR{CSTParser.Curly} && x.args[2].args[3] isa EXPR{CSTParser.Curly}
    else
        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    end
end

function lint(x::EXPR{T}, s::TopLevelScope, L::LintState, server, istop) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    #  NEEDS FIX: 
end

function lint(x::EXPR{CSTParser.Export}, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    exported_names = Set{String}()
    for a in x.args
        if a isa EXPR{IDENTIFIER}
            loc = offset + (0:sizeof(x.val))
            if a.val in exported_names
                push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.DuplicateArgument}(loc, [], "Variable $(x.val) is already exported"))
            else
                push!(exported_names, a.val)
            end
            nsEx = make_name(s.namespace, a.val)
            if !haskey(s.symbols, nsEx)
                push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Variable $(x.val) is exported but not defined within the namespace"))
            end
        end
        offset += a.span
    end
end

function lint(x::EXPR{CSTParser.BinarySyntaxOpCall}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DotOp,Tokens.DOT,false}}
        # NEEDS FIX: check whether module or field of type
        lint(x.args[1], s, L, server, istop)
    elseif x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.WhereOp,Tokens.WHERE,false}} 
        offset = s.current.offset
        params = CSTParser._get_fparams(x)
        for p in params
            
            # name = join(vcat(isempty(s.namespace) ? "toplevel" : s.namespace, p), ".")
            name = make_name(isempty(s.namespace) ? "toplevel" : s.namespace, p)
            v = Variable(p, :DataType, x.args[3])
            if haskey(s.symbols, name)
                push!(s.symbols[name], (v, s.current.offset + (1:x.span), s.current.uri))
            else
                s.symbols[name] = [(v, s.current.offset + (1:x.span), s.current.uri)]
            end
            push!(last(L.locals), name)
        end

        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    else
        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    end
end


function get_symbols(x, s::TopLevelScope, L::LintState) end
function get_symbols(x::EXPR, s::TopLevelScope, L::LintState)
    for v in x.defs
        name = make_name(s.namespace, v.id)
        var_item = (v, s.current.offset + (0:x.span), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
        push!(last(L.locals), name)
    end
end

function get_symbols(x::EXPR{T}, s::TopLevelScope, L::LintState) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    toplevel_symbols(x, s)
end


function remove_symbol(symbols, id)
    if haskey(symbols, id)
        if length(symbols[id]) == 1
            delete!(symbols, id)
        else
            pop!(symbols[id])
        end
    else
        warn("Tried to remove nonexistant symbol: $(id)")
    end
end
