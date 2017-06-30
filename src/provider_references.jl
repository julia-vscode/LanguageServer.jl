mutable struct RefState
    targetid::String
    target::VariableLoc
    refs::Vector{Tuple{Int,String}}
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    y, s, modules, current_namespace = scope(doc, offset, server)
    
    locations = Location[]
    if y isa EXPR{CSTParser.IDENTIFIER}
        id_length = length(y.val)
        id = string(Expr(y))
        ns_name = make_name(s.namespace, Expr(y))
        if haskey(s.symbols, ns_name)
            var_def = last(s.symbols[ns_name])

            rootfile = last(findtopfile(uri, server)[1])

            s = TopLevelScope(ScopePosition(uri, typemax(Int)), ScopePosition(rootfile, 0), false, Dict(), EXPR[], Symbol[], true, true, Dict("toplevel" => []))
            toplevel(server.documents[rootfile].code.ast, s, server)
            s.current.offset = 0
            L = LintState(true, [], [], [])
            R = RefState(ns_name, var_def, [])
            references(server.documents[rootfile].code.ast, s, L, R, server, true)
            for (loc, uri1) in R.refs
                doc1 = server.documents[uri1]
                
                loc1 = loc + (0:id_length)
                push!(locations, Location(uri1, Range(doc1, loc1)))
            end
        end

    end
    response = JSONRPC.Response(get(r.id), locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/references")}}, params)
    return ReferenceParams(params)
end

function references(x::EXPR, s::TopLevelScope, L::LintState, R::RefState, server, istop) 
    for a in x.args
        offset = s.current.offset
        if istop
        else
            get_symbols(a, s, L)
        end

        if contributes_scope(a)
            references(a, s, L, R, server, istop)
        else
            if ismodule(a)
                push!(s.namespace, a.defs[1].id)
            end
            # Add new local scope
            if !(a isa EXPR{IDENTIFIER})
                push!(L.locals, Set{String}())
            end
            references(a, s, L, R, server, false)
            
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

function references(x::EXPR{IDENTIFIER}, s::TopLevelScope, L::LintState, R::RefState, server, istop)
    Ex = Symbol(x.val)
    ns = isempty(L.ns) ? "toplevel" : join(L.ns, ".")
    nsEx = make_name(s.namespace, Ex)

    if nsEx == R.targetid
        if haskey(s.symbols, nsEx)
            uri, loc = last(s.symbols[nsEx])[2:3]
            if uri == R.target[2] && loc == R.target[3]
                push!(R.refs, (s.current.offset, s.current.uri))
            end
        end
    end
end

function references(x::EXPR{Call}, s::TopLevelScope, L::LintState, R::RefState, server, istop)
    if isincludable(x)
        file = Expr(x.args[3])
        file = isabspath(file) ? filepath2uri(file) : joinpath(dirname(s.current.uri), file)
        if file in keys(server.documents)
            oldpos = s.current
            s.current = ScopePosition(file, 0)
            incl_syms = references(server.documents[file].code.ast, s, L, R, server, istop)
            s.current = oldpos
        end
    else
        invoke(references, Tuple{EXPR,TopLevelScope,LintState,RefState,Any,Any}, x, s, L, R, server, istop)
    end
end

# function lint(x::EXPR{CSTParser.Generator}, s::TopLevelScope, L::LintState, server, istop)
#     offset = x.args[1].span + x.args[2].span
#     for i = 3:length(x.args)
#         r = x.args[i]
#         for v in r.defs
#             # name = join(vcat(s.namespace, v.id), ".")
#             name = make_name(s.namespace, v.id)
#             if haskey(s.symbols, name)
#                 push!(s.symbols[name], (v, s.current.offset + (1:r.span), s.current.uri))
#             else
#                 s.symbols[name] = [(v, s.current.offset + (1:r.span), s.current.uri)]
#             end
#             push!(last(L.locals), name)
#         end
#         offset += r.span
#     end
#     lint(x.args[1], s, L, server, istop)
# end

# function lint(x::EXPR{CSTParser.Kw}, s::TopLevelScope, L::LintState, server, istop)
#     s.current.offset += x.args[1].span + x.args[2].span
#     lint(x.args[3], s, L, server, istop)
# end



# function lint(x::EXPR{CSTParser.Quotenode}, s::TopLevelScope, L::LintState, server, istop)
# end

# function lint(x::EXPR{CSTParser.Quote}, s::TopLevelScope, L::LintState, server, istop)
#     # NEEDS FIX: traverse args only linting -> x isa EXPR{UnarySyntaxOpCall} && x.args[1] isa EXPR{OP} where OP <: CSTParser.OPERATOR{CSTParser.PlusOp, Tokens.EX_OR}
# end


# Types
# function lint(x::EXPR{T}, s::TopLevelScope, L::LintState, server, istop) where T <: Union{CSTParser.Struct,CSTParser.Mutable}
#     # NEEDS FIX: allow use of undeclared parameters
# end

# function lint(x::EXPR{CSTParser.Abstract}, s::TopLevelScope, L::LintState, server, istop)
#     # NEEDS FIX: allow use of undeclared parameters
# end


# function lint(x::EXPR{CSTParser.Macro}, s::TopLevelScope, L::LintState, server, istop)
#     s.current.offset += x.args[1].span + x.args[2].span
#     get_symbols(x.args[2], s, L)
#     lint(x.args[3], s, L, server, istop)
# end

# function lint(x::EXPR{CSTParser.x_Str}, s::TopLevelScope, L::LintState, server, istop)
#     s.current.offset += x.args[1].span
#     lint(x.args[2], s, L, server, istop)
# end


# function lint(x::EXPR{CSTParser.Const}, s::TopLevelScope, L::LintState, server, istop)
#     # NEEDS FIX: skip if declaring parameterised type alias
#     if x.args[2] isa EXPR{CSTParser.BinarySyntaxOpCall} && x.args[2].args[1] isa EXPR{CSTParser.Curly} && x.args[2].args[3] isa EXPR{CSTParser.Curly}
#     else
#         invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
#     end
# end

# function lint(x::EXPR{T}, s::TopLevelScope, L::LintState, server, istop) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
#     #  NEEDS FIX: 
# end

# function lint(x::EXPR{CSTParser.BinarySyntaxOpCall}, s::TopLevelScope, L::LintState, server, istop)
#     if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DotOp,Tokens.DOT,false}}
#         # NEEDS FIX: check whether module or field of type
#         lint(x.args[1], s, L, server, istop)
#     elseif x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.WhereOp,Tokens.WHERE,false}} 
#         offset = s.current.offset
#         params = CSTParser._get_fparams(x)
#         for p in params
            
#             # name = join(vcat(isempty(s.namespace) ? "toplevel" : s.namespace, p), ".")
#             name = make_name(isempty(s.namespace) ? "toplevel" : s.namespace, p)
#             v = Variable(p, :DataType, x.args[3])
#             if haskey(s.symbols, name)
#                 push!(s.symbols[name], (v, s.current.offset + (1:x.span), s.current.uri))
#             else
#                 s.symbols[name] = [(v, s.current.offset + (1:x.span), s.current.uri)]
#             end
#             push!(last(L.locals), name)
#         end

#         invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
#     else
#         invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
#     end
# end
