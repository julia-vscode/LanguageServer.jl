mutable struct RefState
    targetid::String
    target::VariableLoc
    refs::Vector{Tuple{Int,String}}
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    if !haskey(server.documents, r.params.textDocument.uri)
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    
    y, s = scope(doc, offset, server)
    
    locations = Location[]
    if y isa EXPR{CSTParser.IDENTIFIER}
        id_length = length(y.val)
        id = string(Expr(y))
        ns_name = make_name(s.namespace, Expr(y))
        if haskey(s.symbols, ns_name)
            var_def = last(s.symbols[ns_name])
            if var_def[1].t in (:Function, :mutable, :immutable, :abstract)
                for i = length(s.symbols[ns_name])-1:-1:1
                    if s.symbols[ns_name][i][1].t in (:Function, :mutable, :immutable, :abstract)
                        var_def = s.symbols[ns_name][i]
                    else
                        break
                    end
                end
            end

            rootfile = last(findtopfile(uri, server)[1])

            s = TopLevelScope(ScopePosition(uri, typemax(Int)), ScopePosition(rootfile, 0), false, Dict(), EXPR[], Symbol[], true, true, Dict{String,Set{String}}("toplevel" => Set{String}()), [])
            toplevel(server.documents[rootfile].code.ast, s, server)
            s.current.offset = 0
            L = LintState([], [], [])
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
    for (i, a) in enumerate(x.args)
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
        elseif x isa EXPR{CSTParser.BinarySyntaxOpCall} 
            if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AnonFuncOp,Tokens.ANON_FUNC,false}} && i == 1
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
                push!(s.namespace, a.args[2].val)
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
        s.current.offset = offset + a.fullspan
    end
    return
end

function references(x::EXPR{IDENTIFIER}, s::TopLevelScope, L::LintState, R::RefState, server, istop)
    Ex = Symbol(x.val)
    ns = isempty(L.ns) ? "toplevel" : join(L.ns, ".")
    nsEx = make_name(s.namespace, Ex)

    if nsEx == R.targetid
        if haskey(s.symbols, nsEx)
            var_def = last(s.symbols[nsEx])
            if var_def[1].t in (:Function, :mutable, :immutable, :abstract)
                for i = length(s.symbols[nsEx])-1:-1:1
                    if s.symbols[nsEx][i][1].t in (:Function, :mutable, :immutable, :abstract)
                        var_def = s.symbols[nsEx][i]
                    else
                        break
                    end
                end
            end
            loc, uri = var_def[2:3]
            if loc == R.target[2] && uri == R.target[3]
                push!(R.refs, (s.current.offset, s.current.uri))
            end
        end
    end
end

function references(x::EXPR{Call}, s::TopLevelScope, L::LintState, R::RefState, server, istop)
    if isincludable(x)
        file = Expr(x.args[3])
        file = isabspath(file) ? filepath2uri(file) : joinpath(dirname(s.current.uri), normpath(file))
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
