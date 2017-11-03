mutable struct RefState
    targetid::String
    target::VariableLoc
    refs::Vector{Tuple{Int,String}}
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    locations = references(doc, offset, server)
    response = JSONRPC.Response(get(r.id), locations)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/references")}}, params)
    return ReferenceParams(params)
end

function references(doc, offset, server)
    y, s = scope(doc, offset, server)
    
    locations = Location[]
    if y isa IDENTIFIER
        id_length = length(str_value(y))
        id = string(Expr(y))
        ns_name = make_name(s.namespace, Expr(y))
        if haskey(s.symbols, ns_name)
            var_def = last(s.symbols[ns_name])
            if var_def.v.t in (:Function, :mutable, :immutable, :abstract)
                for i = length(s.symbols[ns_name])-1:-1:1
                    if s.symbols[ns_name][i].v.t in (:Function, :mutable, :immutable, :abstract)
                        var_def = s.symbols[ns_name][i]
                    else
                        break
                    end
                end
            end

            rootfile = last(findtopfile(doc._uri, server)[1])

            s = TopLevelScope(ScopePosition(doc._uri, typemax(Int)), ScopePosition(rootfile, 0), false, Dict(), EXPR[], Symbol[], true, true, Dict{String,Set{String}}("toplevel" => Set{String}()), Dict{String,Set{String}}("toplevel" => Set{String}()), [])
            toplevel(server.documents[URI2(rootfile)].code.ast, s, server)
            s.current.offset = 0
            L = LintState([], [], [])
            R = RefState(ns_name, var_def, [])
            references(server.documents[URI2(rootfile)].code.ast, s, L, R, server, true)
            for (loc, uri1) in R.refs
                doc1 = server.documents[URI2(uri1)]
                
                loc1 = loc + (0:id_length)
                push!(locations, Location(uri1, Range(doc1, loc1)))
            end
        end
    end
    return locations
end

function references(x::LeafNodes, s::TopLevelScope, L::LintState, R::RefState, server, istop) end

function references(x, s::TopLevelScope, L::LintState, R::RefState, server, istop) 
    for (i, a) in enumerate(x)
        offset = s.current.offset
        if istop
        else
            get_symbols(a, s, L)
        end
        if (x isa EXPR{CSTParser.FunctionDef} || x isa EXPR{CSTParser.Macro}) && i == 2
            _fsig_scope(a, s, server, last(L.locals))
        elseif x isa EXPR{CSTParser.For} && i == 2
            _for_scope(a, s, server, last(L.locals))
        elseif x isa EXPR{CSTParser.Let} && i == 1
            _let_scope(x, s, server, last(L.locals))
        elseif x isa EXPR{CSTParser.Do} && i == 2
            _do_scope(x, s, server, last(L.locals))
        elseif x isa BinarySyntaxOpCall
            if CSTParser.is_anon_func(x.op) && i == 1
                _anon_func_scope(x, s, server, last(L.locals))
            elseif i == 1 && CSTParser.declares_function(x)
                _fsig_scope(a, s, server, last(L.locals))
            end
        elseif x isa EXPR{CSTParser.Generator}
            _generator_scope(x, s, server, last(L.locals))
        elseif x isa EXPR{CSTParser.Try} && i == 3
            _try_scope(x, s, server, last(L.locals))
        end

        if contributes_scope(a)
            references(a, s, L, R, server, istop)
        else
            if ismodule(a)
                push!(s.namespace, str_value(a.args[2]))
            end
            # Add new local scope
            if !(a isa IDENTIFIER)
                push!(L.locals, Set{String}())
            end
            references(a, s, L, R, server, false)
            
            # Delete local scope
            if !(a isa IDENTIFIER)
                for k in pop!(L.locals)
                    remove_symbol(s.symbols, k)
                end
            end
            if ismodule(a)
                pop!(s.namespace)
            end
        end
        
        s.current.offset = offset + a.fullspan
    end
    return
end

function references(x::IDENTIFIER, s::TopLevelScope, L::LintState, R::RefState, server, istop)
    Ex = Symbol(str_value(x))
    ns = isempty(L.ns) ? "toplevel" : join(L.ns, ".")
    nsEx = make_name(s.namespace, Ex)

    if nsEx == R.targetid
        if haskey(s.symbols, nsEx)
            var_def = last(s.symbols[nsEx])
            if var_def.v.t in (:Function, :mutable, :immutable, :abstract)
                for i = length(s.symbols[nsEx])-1:-1:1
                    if s.symbols[nsEx][i].v.t in (:Function, :mutable, :immutable, :abstract)
                        var_def = s.symbols[nsEx][i]
                    else
                        break
                    end
                end
            end
            
            if var_def.loc == R.target.loc && var_def.uri == R.target.uri
                push!(R.refs, (s.current.offset, s.current.uri))
            end
        end
    end
end

function references(x::EXPR{Call}, s::TopLevelScope, L::LintState, R::RefState, server, istop)
    if isincludable(x)
        file = Expr(x.args[3])
        file = isabspath(file) ? filepath2uri(file) : joinuriwithpath(dirname(s.current.uri), file)
        if haskey(server.documents, URI2(file))
            oldpos = s.current
            s.current = ScopePosition(file, 0)
            incl_syms = references(server.documents[URI2(file)].code.ast, s, L, R, server, istop)
            s.current = oldpos
        end
    else
        invoke(references, Tuple{EXPR,TopLevelScope,LintState,RefState,Any,Any}, x, s, L, R, server, istop)
    end
end
