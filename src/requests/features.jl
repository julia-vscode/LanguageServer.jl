function get_signatures(b, tls, sigs, server, visited=nothing) end # Fallback

function get_signatures(b::StaticLint.Binding, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, server, visited=StaticLint.Binding[])
    if b in visited                                      # TODO: remove
        throw(LSInfiniteLoop("Possible infinite loop.")) # TODO: remove
    else                                                 # TODO: remove
        push!(visited, b)                                # TODO: remove
    end                                                  # TODO: remove
    if b.type == StaticLint.CoreTypes.Function && b.val isa EXPR && CSTParser.defines_function(b.val)
        get_siginfo_from_call(b.val, sigs)
    elseif b.val isa EXPR && CSTParser.defines_struct(b.val)
        args = b.val.args[3]
        if length(args) > 0
            inner_constructor_i = findfirst(a -> CSTParser.defines_function(a), args.args)
            if inner_constructor_i !== nothing
                get_siginfo_from_call(args.args[inner_constructor_i], sigs)
            else
                params = ParameterInformation[]
                for field in args.args
                    field_name = CSTParser.rem_decl(field)
                    push!(params, ParameterInformation(field_name isa EXPR && CSTParser.isidentifier(field_name) ? valof(field_name) : "", missing))
                end
                push!(sigs, SignatureInformation(string(Expr(b.val)), "", params))
            end
        end
        return
    elseif b.val isa SymbolServer.SymStore
        return get_signatures(b.val, tls, sigs, server)
    else
        return
    end

    get_signatures(b.prev, tls, sigs, server, visited)
end

function get_signatures(b::T, tls::StaticLint.Scope, sigs::Vector{SignatureInformation}, server, visited=nothing) where T <: Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}
    StaticLint.iterate_over_ss_methods(b, tls, server, function (m)
        push!(sigs, SignatureInformation(string(m), "", (a -> ParameterInformation(string(a[1]), string(a[2]))).(m.sig)))
        return false
    end)
end


function get_siginfo_from_call(call, sigs) end # Fallback

function get_siginfo_from_call(call::EXPR, sigs)
    sig = CSTParser.rem_where_decl(CSTParser.get_sig(call))
    params = ParameterInformation[]
    if sig isa EXPR && sig.args !== nothing
        for i = 2:length(sig.args)
            if (argbinding = bindingof(sig.args[i])) !== nothing
                push!(params, ParameterInformation(valof(argbinding.name) isa String ? valof(argbinding.name) : "", missing))
            end
        end
        push!(sigs, SignatureInformation(string(Expr(sig)), "", params))
    end
end

function textDocument_signatureHelp_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, URI2(params.textDocument.uri))
    sigs = SignatureInformation[]
    offset = get_offset(doc, params.position)
    rng = Range(doc, offset:offset)
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
            get_signatures(f_binding, tls, sigs, server)
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

# TODO: should be in StaticLint. visited check is costly.
resolve_shadow_binding(b) = b
function resolve_shadow_binding(b::StaticLint.Binding, visited=StaticLint.Binding[])
    if b in visited
        throw(LSInfiniteLoop("Inifinite loop in bindings."))
    else
        push!(visited, b)
    end
    if b.val isa StaticLint.Binding
        return resolve_shadow_binding(b.val, visited)
    else
        return b
    end
end

function get_definitions(x, tls, server, locations, visited=nothing) end # Fallback

function get_definitions(x::SymbolServer.ModuleStore, tls, server, locations, visited=nothing)
    if haskey(x.vals, :eval) && x[:eval] isa SymbolServer.FunctionStore
        get_definitions(x[:eval], tls, server, locations, visited)
    end
end

function get_definitions(x::T, tls, server, locations, visited=nothing) where T <: Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}
    StaticLint.iterate_over_ss_methods(x, tls, server, function (m)
        try
            if isfile(m.file)
                push!(locations, Location(filepath2uri(m.file), Range(m.line - 1, 0, m.line - 1, 0)))
            end
        catch err
            isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        end
        return false
    end)
end

function get_definitions(b::StaticLint.Binding, tls, server, locations, visited=StaticLint.Binding[])
    if b in visited                                      # TODO: remove
        throw(LSInfiniteLoop("Possible infinite loop.")) # TODO: remove
    else                                                 # TODO: remove
        push!(visited, b)                                # TODO: remove
    end                                                  # TODO: remove

    if !(b.val isa EXPR)
        return get_definitions(b.val, tls, server, locations, visited)
    end
    doc1, o = get_file_loc(b.val)
    if doc1 isa Document
        push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:b.val.span))))
    end

    if b.type === StaticLint.CoreTypes.Function && b.prev isa StaticLint.Binding && (b.prev.type === StaticLint.CoreTypes.Function || b.prev.type === StaticLint.CoreTypes.DataType)
        return get_definitions(b.prev, tls, server, locations, visited)
    end
end

function textDocument_definition_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    locations = Location[]
    doc = getdocument(server, URI2(params.textDocument.uri))
    offset = get_offset(doc, params.position)
    x = get_expr1(getcst(doc), offset)
    if x isa EXPR && StaticLint.hasref(x)
        # Replace with own function to retrieve references (with loop saftey-breaker)
        b = refof(x)
        b = resolve_shadow_binding(b)
        (tls = StaticLint.retrieve_toplevel_scope(x)) === nothing && return locations
        get_definitions(b, tls, server, locations)
    elseif x isa EXPR && CSTParser.isstringliteral(x)
        # TODO: move to its own function
        if sizeof(valof(x)) < 256 # AUDIT: OK
            try
                if isabspath(valof(x)) && isfile(valof(x))
                    push!(locations, Location(filepath2uri(valof(x)), Range(0, 0, 0, 0)))
                elseif !isempty(getpath(doc)) && isfile(joinpath(_dirname(getpath(doc)), valof(x)))
                    push!(locations, Location(filepath2uri(joinpath(_dirname(getpath(doc)), valof(x))), Range(0, 0, 0, 0)))
                end
            catch err
                isa(err, Base.IOError) ||
                    isa(err, Base.SystemError) ||
                    (VERSION == v"1.2.0" && isa(err, ErrorException) && err.msg == "type Nothing has no field captures ") ||
                    rethrow()
            end
        end
    end

    return locations
end

function get_file_loc(x::EXPR, offset=0, c=nothing)
    if c !== nothing
        for a in x
            a == c && break
            offset += a.fullspan
        end
    end
    if parentof(x) !== nothing
        return get_file_loc(parentof(x), offset, x)
    elseif headof(x) === :file && StaticLint.hasmeta(x)
        return x.meta.error, offset
    else
        return nothing, offset
    end
end

function textDocument_formatting_request(params::DocumentFormattingParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, URI2(params.textDocument.uri))
    newcontent = DocumentFormat.format(get_text(doc), server.format_options)
    end_l, end_c = get_position_at(doc, sizeof(get_text(doc))) # AUDIT: OK
    lsedits = TextEdit[TextEdit(Range(0, 0, end_l, end_c), newcontent)]

    return lsedits
end

function find_references(textDocument::TextDocumentIdentifier, position::Position, server)
    locations = Location[]
    doc = getdocument(server, URI2(textDocument.uri))
    offset = get_offset(doc, position)
    x = get_expr1(getcst(doc), offset)
    if x isa EXPR && StaticLint.hasref(x) && refof(x) isa StaticLint.Binding
        refs = find_references(refof(x))
        for r in refs
            doc1, o = get_file_loc(r)
            if doc1 isa Document
                push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:r.span))))
            end
        end
    end
    return locations
end

function find_references(b::StaticLint.Binding, refs=EXPR[], from_end=false)
    if !from_end && (b.type === StaticLint.CoreTypes.Function || b.type === StaticLint.CoreTypes.DataType)
        b = StaticLint.last_method(b)
    end
    for r in b.refs
        r isa EXPR && push!(refs, r)
    end
    if b.prev isa StaticLint.Binding && (b.prev.type === StaticLint.CoreTypes.Function || b.prev.type === StaticLint.CoreTypes.DataType)
        return find_references(b.prev, refs, true)
    else
        return refs
    end
end

function textDocument_references_request(params::ReferenceParams, server::LanguageServerInstance, conn)
    return find_references(params.textDocument, params.position, server)
end

function textDocument_rename_request(params::RenameParams, server::LanguageServerInstance, conn)
    tdes = Dict{String,TextDocumentEdit}()
    locations = find_references(params.textDocument, params.position, server)

    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, params.newName))
        else
            doc = getdocument(server, URI2(loc.uri))
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, doc._version), [TextEdit(loc.range, params.newName)])
        end
    end

    return WorkspaceEdit(missing, collect(values(tdes)))
end


is_valid_binding_name(name) = false
function is_valid_binding_name(name::EXPR)
    (headof(name) === :IDENTIFIER && valof(name) isa String && !isempty(valof(name))) ||
    CSTParser.isoperator(name) ||
    (headof(name) === :NONSTDIDENTIFIER && length(name.args) == 2 && valof(name.args[2]) isa String && !isempty(valof(name.args[2])))
end
function get_name_of_binding(name::EXPR)
    if headof(name) === :IDENTIFIER
        valof(name)
    elseif CSTParser.isoperator(name)
        string(Expr(name))
    elseif headof(name) === :NONSTDIDENTIFIER
        valof(name.args[2])
    else
        ""
    end
end

function textDocument_documentSymbol_request(params::DocumentSymbolParams, server::LanguageServerInstance, conn)
    syms = SymbolInformation[]
    uri = params.textDocument.uri
    doc = getdocument(server, URI2(uri))

    bs = collect_bindings_w_loc(getcst(doc))
    for x in bs
        p, b = x[1], x[2]
        !(b.val isa EXPR) && continue
        !is_valid_binding_name(b.name) && continue
        push!(syms, SymbolInformation(get_name_of_binding(b.name), _binding_kind(b, server), false, Location(doc._uri, Range(doc, p)), missing))
    end
    return syms
end

function collect_bindings_w_loc(x::EXPR, pos=0, bindings=Tuple{UnitRange{Int},StaticLint.Binding}[])
    if bindingof(x) !== nothing
        push!(bindings, (pos .+ (0:x.span), bindingof(x)))
    end
    if length(x) > 0
        for a in x
            collect_bindings_w_loc(a, pos, bindings)
            pos += a.fullspan
        end
    end
    return bindings
end

function collect_toplevel_bindings_w_loc(x::EXPR, pos=0, bindings=Tuple{UnitRange{Int},StaticLint.Binding}[]; query="")
    if bindingof(x) isa StaticLint.Binding && valof(bindingof(x).name) isa String && bindingof(x).val isa EXPR && startswith(valof(bindingof(x).name), query)
        push!(bindings, (pos .+ (0:x.span), bindingof(x)))
    end
    if scopeof(x) !== nothing && !(headof(x) === :file || CSTParser.defines_module(x))
        return bindings
    end
    if length(x) > 0
        for a in x
            collect_toplevel_bindings_w_loc(a, pos, bindings, query=query)
            pos += a.fullspan
        end
    end
    return bindings
end

function _binding_kind(b, server)
    if b isa StaticLint.Binding
        if b.type === nothing
            return 13
        elseif b.type == StaticLint.CoreTypes.Module
            return 2
        elseif b.type == StaticLint.CoreTypes.Function
            return 12
        elseif b.type == StaticLint.CoreTypes.String
            return 15
        elseif b.type == StaticLint.CoreTypes.Int || b.type == StaticLint.CoreTypes.Float64
            return 16
        elseif b.type == StaticLint.CoreTypes.DataType
            return 23
        else
            return 13
        end
    elseif b isa SymbolServer.ModuleStore
        return 2
    elseif b isa SymbolServer.MethodStore
        return 6
    elseif b isa SymbolServer.FunctionStore
        return 12
    elseif b isa SymbolServer.DataTypeStore
        return 23
    else
        return 13
    end
end

function julia_getModuleAt_request(params::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = URI2(params.textDocument.uri)

    if hasdocument(server, uri)
        doc = getdocument(server, uri)
        if doc._version == params.version
            offset = get_offset2(doc, params.position.line, params.position.character)
            x = get_expr(getcst(doc), offset)
            if x isa EXPR
                scope = StaticLint.retrieve_scope(x)
                if scope !== nothing
                    return get_module_of(scope)
                end
            end
        else
            return mismatched_version_error(uri, doc, params, "getModuleAt")
        end
    else
        return nodocuemnt_error(uri)
    end
    return "Main"
end

function get_module_of(s::StaticLint.Scope, ms=[])
    if CSTParser.defines_module(s.expr) && CSTParser.isidentifier(s.expr.args[2])
        pushfirst!(ms, StaticLint.valofid(s.expr.args[2]))
    end
    if parentof(s) isa StaticLint.Scope
        return get_module_of(parentof(s), ms)
    else
        return isempty(ms) ? "Main" : join(ms, ".")
    end
end

function julia_getDocAt_request(params::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = URI2(params.textDocument.uri)
    hasdocument(server, uri) || return nodocuemnt_error(uri)

    doc = getdocument(server, uri)
    if doc._version !== params.version
        return mismatched_version_error(uri, doc, params, "getDocAt")
    end

    x = get_expr1(getcst(doc), get_offset(doc, params.position))
    x isa EXPR && CSTParser.isoperator(x) && resolve_op_ref(x, server)
    documentation = get_hover(x, "", server)

    return documentation
end

# TODO: handle documentation resolving properly, respect how Documenter handles that
function julia_getDocFromWord_request(word::String, server::LanguageServerInstance, conn)
    documentation = ""
    word_sym = Symbol(word)
    traverse_by_name(getsymbolserver(server)) do sym, val
        if sym === word_sym
            documentation = get_hover(val, documentation, server)
        end
    end
    return documentation
end
