

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

function get_definitions(x, tls, server, locations) end # Fallback

function get_definitions(x::SymbolServer.ModuleStore, tls, server, locations)
    if haskey(x.vals, :eval) && x[:eval] isa SymbolServer.FunctionStore
        get_definitions(x[:eval], tls, server, locations)
    end
end

function get_definitions(x::Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}, tls, server, locations)
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

function get_definitions(b::StaticLint.Binding, tls, server, locations)
    if !(b.val isa EXPR)
        get_definitions(b.val, tls, server, locations)
    end
    if b.type === StaticLint.CoreTypes.Function || b.type === StaticLint.CoreTypes.DataType
        for ref in b.refs
            method = StaticLint.get_method(ref)
            if method !== nothing
                get_definitions(method, tls, server, locations)
            end
        end
    elseif b.val isa EXPR
        get_definitions(b.val, tls, server, locations)
    end
end

function get_definitions(x::EXPR, tls::StaticLint.Scope, server, locations)
    doc1, o = get_file_loc(x)
    if doc1 isa Document
        push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:x.span))))
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
        if valof(x) isa String && sizeof(valof(x)) < 256 # AUDIT: OK
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
        for r in refof(x).refs
            if r isa EXPR
                doc1, o = get_file_loc(r)
                if doc1 isa Document
                    push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:r.span))))
                end
            end
        end
    end
    return locations
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

    return collect_document_symbols(getcst(doc), server, doc)
end

function collect_document_symbols(x::EXPR, server::LanguageServerInstance, doc, pos=0, symbols=[])
    if bindingof(x) !== nothing
        b =  bindingof(x)
        if b.val isa EXPR && is_valid_binding_name(b.name)
            ds = DocumentSymbol(
                get_name_of_binding(b.name), # name
                missing, # detail
                _binding_kind(b, server), # kind
                false, # deprecated
                Range(doc, (pos .+ (0:x.span))), # range
                Range(doc, (pos .+ (0:x.span))), # selection range
                DocumentSymbol[] # children
            )
            push!(symbols, ds)
            symbols = ds.children
        end
    end
    if length(x) > 0
        for a in x
            collect_document_symbols(a, server, doc, pos, symbols)
            pos += a.fullspan
        end
    end
    return symbols
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
            offset = get_offset2(doc, params.position.line, params.position.character, true)
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
function julia_getDocFromWord_request(params::NamedTuple{(:word,),Tuple{String}}, server::LanguageServerInstance, conn)
    exact_matches = []
    approx_matches = []
    word_sym = Symbol(params.word)
    traverse_by_name(getsymbolserver(server)) do sym, val
        is_exact_match = sym === word_sym
        # this would ideally use the Damerau-Levenshtein distance or even something fancier:
        is_match = is_exact_match || REPL.levenshtein(string(sym), string(word_sym)) <= 1
        if is_match
            val = get_hover(val, "", server)
            if !isempty(val)
                push!(is_exact_match ? exact_matches : approx_matches, val)
            end
        end
    end
    if isempty(exact_matches) && isempty(approx_matches)
        return "No results found."
    else
        return join(isempty(exact_matches) ? approx_matches[1:min(end, 10)] : exact_matches, "\n---\n")
    end
end
