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
            lint(a, s, L, server, false)
            
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
    nsEx = make_name(s.namespace, Ex)
    found = Ex in BaseCoreNames

    if !found
        if haskey(s.symbols, Ex)
            found = true
        end
    end
    if !found
        if haskey(s.symbols, nsEx)
            found = true
        end
    end
    
    ns = isempty(L.ns) ? "toplevel" : join(L.ns, ".")

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

function lint(x::EXPR{CSTParser.Generator}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].span + x.args[2].span
    for i = 3:length(x.args)
        r = x.args[i]
        for v in r.defs
            # name = join(vcat(s.namespace, v.id), ".")
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

function lint(x::EXPR{CSTParser.Kw}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].span + x.args[2].span
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Quotenode}, s::TopLevelScope, L::LintState, server, istop)
end

function lint(x::EXPR{CSTParser.Quote}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: traverse args only linting -> x isa EXPR{UnarySyntaxOpCall} && x.args[1] isa EXPR{OP} where OP <: CSTParser.OPERATOR{CSTParser.PlusOp, Tokens.EX_OR}
end


# Types
function lint(x::EXPR{T}, s::TopLevelScope, L::LintState, server, istop) where T <: Union{CSTParser.Struct,CSTParser.Mutable}
    # NEEDS FIX: allow use of undeclared parameters
end

function lint(x::EXPR{CSTParser.Abstract}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: allow use of undeclared parameters
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
