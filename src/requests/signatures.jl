function textDocument_signatureHelp_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    sigs = SignatureInformation[]
    # TODO The following call is just here for diagnostics
    # We currently have crashes in the call to get_offset in crash reporting
    # but they are fairly rare. So the idea here is to see whether we also get_expr
    # crashes in index_at or not. If we still see crashes in get_offset after this here
    # is merged, then the bug is simply in get_offset and we should migrate this function
    # over to use index_at. If not, then there might still be a problem in the sync protocol.
    index_at(get_text_document(doc), params.position)
    offset = get_offset(doc, params.position)
    x = get_expr(getcst(doc), offset)
    arg = 0
    if x isa EXPR && parentof(x) isa EXPR && CSTParser.iscall(parentof(x))
        if CSTParser.isidentifier(parentof(x).args[1])
            call_name = parentof(x).args[1]
        elseif CSTParser.iscurly(parentof(x).args[1]) && CSTParser.isidentifier(parentof(x).args[1].args[1])
            call_name = parentof(x).args[1].args[1]
        elseif CSTParser.is_getfield_w_quotenode(parentof(x).args[1])
            call_name = parentof(x).args[1].args[2].args[1]
        else
            call_name = nothing
        end
        if call_name !== nothing && (f_binding = refof(call_name)) !== nothing && (tls = StaticLint.retrieve_toplevel_scope(call_name)) !== nothing
            get_signatures(f_binding, tls, sigs, getenv(doc, server))
        end
    end
    if (isempty(sigs) || (headof(x) === :RPAREN))
        return SignatureHelp(SignatureInformation[], 0, 0)
    end

    if headof(x) === :LPAREN
        arg = 0
    else
        arg = sum(headof(a) === :COMMA for a in parentof(x).trivia)
    end
    return SignatureHelp(filter(s -> length(s.parameters) > arg, sigs), 0, arg)
end

function get_signatures(b, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env) end

function get_signatures(b::StaticLint.Binding, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env)

    if b.val isa StaticLint.Binding
        get_signatures(b.val, tls, sigs, env)
    end
    if b.type == StaticLint.CoreTypes.Function || b.type == StaticLint.CoreTypes.DataType
        b.val isa SymbolServer.SymStore && get_signatures(b.val, tls, sigs, env)
        for ref in b.refs
            method = StaticLint.get_method(ref)
            if method !== nothing
                get_signatures(method, tls, sigs, env)
            end
        end
    end
end

function get_signatures(b::T, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env) where T <: Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}
    StaticLint.iterate_over_ss_methods(b, tls, env, function (m)
        push!(sigs, SignatureInformation(string(m), "", (a -> ParameterInformation(string(a[1]), string(a[2]))).(m.sig)))
        return false
    end)
end

function get_signatures(x::EXPR, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env)
    if CSTParser.defines_function(x)
        sig = CSTParser.rem_where_decl(CSTParser.get_sig(x))
        params = ParameterInformation[]
        if sig isa EXPR && sig.args !== nothing
            for i = 2:length(sig.args)
                if (argbinding = bindingof(sig.args[i])) !== nothing
                    push!(params, ParameterInformation(valof(argbinding.name) isa String ? valof(argbinding.name) : "", missing))
                end
            end
            push!(sigs, SignatureInformation(string(to_codeobject(sig)), "", params))
        end
    elseif CSTParser.defines_struct(x)
        args = x.args[3]
        if length(args) > 0
            if !any(CSTParser.defines_function, args.args)
                params = ParameterInformation[]
                for field in args.args
                    field_name = CSTParser.rem_decl(field)
                    push!(params, ParameterInformation(field_name isa EXPR && CSTParser.isidentifier(field_name) ? valof(field_name) : "", missing))
                end
                push!(sigs, SignatureInformation(string(to_codeobject(x)), "", params))
            end
        end
    end
end
