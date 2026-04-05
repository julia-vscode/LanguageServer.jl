function textDocument_signatureHelp_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    meta_dict, _ = get_meta_data(server, uri)
    sigs = SignatureInformation[]
    offset = get_offset(st, params.position)
    x = get_expr(jw_cst(server, uri), offset)

    sigs = collect_signatures(x, server, uri, meta_dict)

    if (isempty(sigs) || (headof(x) === :RPAREN))
        return SignatureHelp(SignatureInformation[], 0, 0)
    end

    arg = fcall_arg_number(x)

    return SignatureHelp(filter(s -> length(s.parameters) > arg, sigs), 0, arg)
end

function fcall_arg_number(x)
    if headof(x) === :LPAREN
        0
    else
        sum(headof(a) === :COMMA for a in parentof(x).trivia)
    end
end

function collect_signatures(x, server, uri, meta_dict)
    sigs = SignatureInformation[]

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
        if call_name !== nothing && (f_binding = refof(call_name, meta_dict)) !== nothing && (tls = retrieve_toplevel_scope(call_name, meta_dict)) !== nothing
            get_signatures(f_binding, tls, sigs, getenv(server, uri), meta_dict)
        end
    end

    return sigs
end

function get_signatures(b, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env, meta_dict) end

function get_signatures(b::StaticLint.Binding, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env, meta_dict)
    if b.val isa StaticLint.Binding
        get_signatures(b.val, tls, sigs, env, meta_dict)
    end
    if b.type == StaticLint.CoreTypes.Function || b.type == StaticLint.CoreTypes.DataType
        b.val isa SymbolServer.SymStore && get_signatures(b.val, tls, sigs, env, meta_dict)
        for ref in b.refs
            method = StaticLint.get_method(ref)
            if method !== nothing
                get_signatures(method, tls, sigs, env, meta_dict)
            end
        end
    end
end

function get_signatures(b::T, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env, meta_dict) where T <: Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}
    StaticLint.iterate_over_ss_methods(b, tls, env, function (m)
        push!(sigs, SignatureInformation(string(m), "", (a -> ParameterInformation(string(a[1]), string(a[2]))).(m.sig)))
        return false
    end)
end

function get_signatures(x::EXPR, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, env, meta_dict)
    if CSTParser.defines_function(x)
        sig = CSTParser.rem_where_decl(CSTParser.get_sig(x))
        params = ParameterInformation[]
        if sig isa EXPR && sig.args !== nothing
            for i = 2:length(sig.args)
                if (argbinding = bindingof(sig.args[i], meta_dict)) !== nothing
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
