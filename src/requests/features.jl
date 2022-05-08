

# TODO: should be in StaticLint. visited check is costly.
resolve_shadow_binding(b) = b
function resolve_shadow_binding(b::StaticLint.Binding, visited=StaticLint.Binding[])
    if b in visited
        throw(LSInfiniteLoop("Infinite loop in bindings."))
    else
        push!(visited, b)
    end
    if b.val isa StaticLint.Binding
        return resolve_shadow_binding(b.val, visited)
    else
        return b
    end
end

function get_definitions(x, tls, env, locations) end # Fallback

function get_definitions(x::SymbolServer.ModuleStore, tls, env, locations)
    if haskey(x.vals, :eval) && x[:eval] isa SymbolServer.FunctionStore
        get_definitions(x[:eval], tls, env, locations)
    end
end

function get_definitions(x::Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}, tls, env, locations)
    StaticLint.iterate_over_ss_methods(x, tls, env, function (m)
        if safe_isfile(m.file)
            push!(locations, Location(filepath2uri(m.file), Range(m.line - 1, 0, m.line - 1, 0)))
        end
        return false
    end)
end

function get_definitions(b::StaticLint.Binding, tls, env, locations)
    if !(b.val isa EXPR)
        get_definitions(b.val, tls, env, locations)
    end
    if b.type === StaticLint.CoreTypes.Function || b.type === StaticLint.CoreTypes.DataType
        for ref in b.refs
            method = StaticLint.get_method(ref)
            if method !== nothing
                get_definitions(method, tls, env, locations)
            end
        end
    elseif b.val isa EXPR
        get_definitions(b.val, tls, env, locations)
    end
end

function get_definitions(x::EXPR, tls::StaticLint.Scope, env, locations)
    doc1, o = get_file_loc(x)
    if doc1 isa Document
        push!(locations, Location(get_uri(doc1), Range(doc1, o .+ (0:x.span))))
    end
end

safe_isfile(s::Symbol) = safe_isfile(string(s))
safe_isfile(::Nothing) = false
function safe_isfile(s::AbstractString)
    try
        !occursin("\0", s) && isfile(s)
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        false
    end
end

function textDocument_definition_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    locations = Location[]
    doc = getdocument(server, params.textDocument.uri)
    offset = get_offset(doc, params.position)
    x = get_expr1(getcst(doc), offset)
    if x isa EXPR && StaticLint.hasref(x)
        # Replace with own function to retrieve references (with loop saftey-breaker)
        b = refof(x)
        b = resolve_shadow_binding(b)
        (tls = StaticLint.retrieve_toplevel_scope(x)) === nothing && return locations
        get_definitions(b, tls, getenv(doc, server), locations)
    end

    return locations
end

function descend(x::EXPR, target::EXPR, offset=0)
    x == target && return (true, offset)
    for c in x
        if c == target
            return true, offset
        end

        found, o = descend(c, target, offset)
        if found
            return true, o
        end
        offset += c.fullspan
    end
    return false, offset
end
function get_file_loc(x::EXPR, offset=0, c=nothing)
    parent = x
    while parentof(parent) !== nothing
        parent = parentof(parent)
    end

    if parent === nothing
        return nothing, offset
    end

    _, offset = descend(parent, x)

    if headof(parent) === :file && StaticLint.hasmeta(parent)
        return parent.meta.error, offset
    end
    return nothing, offset
end

function search_file(filename, dir, topdir)
    parent_dir = dirname(dir)
    return if (!startswith(dir, topdir) || parent_dir == dir || isempty(dir))
        nothing
    else
        path = joinpath(dir, filename)
        isfile(path) ? path : search_file(filename, parent_dir, topdir)
    end
end

function get_juliaformatter_config(doc, server)
    path = get_path(doc)

    # search through workspace for a `.JuliaFormatter.toml`
    workspace_dirs = sort(filter(f -> startswith(path, f), collect(server.workspaceFolders)), by = length, rev = true)
    config_path = length(workspace_dirs) > 0 ?
        search_file(JuliaFormatter.CONFIG_FILE_NAME, path, workspace_dirs[1]) :
        nothing

    config_path === nothing && return nothing

    @debug "Found JuliaFormatter config at $(config_path)"
    return JuliaFormatter.parse_config(config_path)
end

function default_juliaformatter_config(params)
    return (
        indent = params.options.tabSize,
        annotate_untyped_fields_with_any = false,
        join_lines_based_on_source = true,
        trailing_comma = nothing,
        margin = 10_000,
        always_for_in = nothing,
        whitespace_in_kwargs = false
    )
end

function textDocument_formatting_request(params::DocumentFormattingParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)

    config = get_juliaformatter_config(doc, server)

    newcontent = try
        format_text(get_text(doc), params, config)
    catch err
        return JSONRPC.JSONRPCError(
            -32000,
            "Failed to format document: $err.",
            nothing
        )
    end

    end_l, end_c = get_position_from_offset(doc, sizeof(get_text(doc))) # AUDIT: OK
    lsedits = TextEdit[TextEdit(Range(0, 0, end_l, end_c), newcontent)]

    return lsedits
end

function format_text(text::AbstractString, params, config)
    if config === nothing
        return JuliaFormatter.format_text(text; default_juliaformatter_config(params)...)
    else
        # Some valid options in config file are not valid for format_text
        VALID_OPTIONS = (fieldnames(JuliaFormatter.Options)..., :style)
        config = filter(p -> in(first(p), VALID_OPTIONS), JuliaFormatter.kwargs(config))
        return JuliaFormatter.format_text(text; config...)
    end
end

function textDocument_range_formatting_request(params::DocumentRangeFormattingParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    cst = getcst(doc)

    expr = get_inner_expr(cst, get_offset(doc, params.range.start):get_offset(doc, params.range.stop))

    if expr === nothing
        return nothing
    end

    while !(expr.head in (:for, :if, :function, :module, :file, :call))
        if expr.parent !== nothing
            expr = expr.parent
        else
            return nothing
        end
    end

    _, offset = get_file_loc(expr)
    l1, c1 = get_position_from_offset(doc, offset)
    c1 = 0
    start_offset = index_at(doc, Position(l1, c1))
    l2, c2 = get_position_from_offset(doc, offset + expr.span)

    text = get_text(doc)[start_offset:offset+expr.span]

    longest_prefix = nothing
    for line in eachline(IOBuffer(text))
        (isempty(line) || occursin(r"^\s*$", line)) && continue
        idx = 0
        for c in line
            if c == ' ' || c == '\t'
                idx += 1
            else
                break
            end
        end
        line = line[1:idx]
        longest_prefix = CSTParser.longest_common_prefix(something(longest_prefix, line), line)
    end

    config = get_juliaformatter_config(doc, server)

    newcontent = try
        format_text(text, params, config)
    catch err
        return JSONRPC.JSONRPCError(
            -33000,
            "Failed to format document: $err.",
            nothing
        )
    end

    if longest_prefix !== nothing && !isempty(longest_prefix)
        io = IOBuffer()
        for line in eachline(IOBuffer(newcontent), keep=true)
            print(io, longest_prefix, line)
        end
        newcontent = String(take!(io))
    end

    lsedits = TextEdit[TextEdit(Range(l1, c1, l2, c2), newcontent)]

    return lsedits
end

function find_references(textDocument::TextDocumentIdentifier, position::Position, server)
    locations = Location[]
    doc = getdocument(server, textDocument.uri)
    offset = get_offset(doc, position)
    x = get_expr1(getcst(doc), offset)
    x === nothing && return locations
    for_each_ref(x) do r, doc1, o
        push!(locations, Location(get_uri(doc1), Range(doc1, o .+ (0:r.span))))
    end
    return locations
end

function for_each_ref(f, identifier::EXPR)
    if identifier isa EXPR && StaticLint.hasref(identifier) && refof(identifier) isa StaticLint.Binding
        for r in refof(identifier).refs
            if r isa EXPR
                doc1, o = get_file_loc(r)
                if doc1 isa Document
                    f(r, doc1, o)
                end
            end
        end
    end
end

function textDocument_references_request(params::ReferenceParams, server::LanguageServerInstance, conn)
    return find_references(params.textDocument, params.position, server)
end

function textDocument_rename_request(params::RenameParams, server::LanguageServerInstance, conn)
    tdes = Dict{URI,TextDocumentEdit}()
    locations = find_references(params.textDocument, params.position, server)

    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, params.newName))
        else
            doc = getdocument(server, loc.uri)
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, get_version(doc)), [TextEdit(loc.range, params.newName)])
        end
    end

    return WorkspaceEdit(missing, collect(values(tdes)))
end

function textDocument_prepareRename_request(params::PrepareRenameParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    x = get_expr1(getcst(doc), get_offset(doc, params.position))
    x isa EXPR || return nothing
    _, x_start_offset = get_file_loc(x)
    x_range = Range(doc, x_start_offset .+ (0:x.span))
    return x_range
end

function is_callable_object_binding(name::EXPR)
    CSTParser.isoperator(headof(name)) && valof(headof(name)) === "::" && length(name.args) >= 1
end
is_valid_binding_name(name) = false
function is_valid_binding_name(name::EXPR)
    (headof(name) === :IDENTIFIER && valof(name) isa String && !isempty(valof(name))) ||
    CSTParser.isoperator(name) ||
    (headof(name) === :NONSTDIDENTIFIER && length(name.args) == 2 && valof(name.args[2]) isa String && !isempty(valof(name.args[2]))) ||
    is_callable_object_binding(name)
end
function get_name_of_binding(name::EXPR)
    if headof(name) === :IDENTIFIER
        valof(name)
    elseif CSTParser.isoperator(name)
        string(to_codeobject(name))
    elseif headof(name) === :NONSTDIDENTIFIER
        valof(name.args[2])
    elseif is_callable_object_binding(name)
        string(to_codeobject(name))
    else
        ""
    end
end

function textDocument_documentSymbol_request(params::DocumentSymbolParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    doc = getdocument(server, uri)

    return collect_document_symbols(getcst(doc), server, doc)
end

function collect_document_symbols(x::EXPR, server::LanguageServerInstance, doc, pos=0, symbols=DocumentSymbol[])
    if bindingof(x) !== nothing
        b =  bindingof(x)
        if b.val isa EXPR && is_valid_binding_name(b.name)
            ds = DocumentSymbol(
                get_name_of_binding(b.name), # name
                missing, # detail
                _binding_kind(b), # kind
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

function _binding_kind(b)
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
    uri = params.textDocument.uri

    if hasdocument(server, uri)
        doc = getdocument(server, uri)
        if get_version(doc) == params.version
            offset = index_at(doc, params.position, true)
            x, p = get_expr_or_parent(getcst(doc), offset, 1)
            if x isa EXPR
                if x.head === :MODULE || x.head === :IDENTIFIER || x.head === :END
                    if x.parent !== nothing && x.parent.head === :module
                        x = x.parent
                        if CSTParser.defines_module(x)
                            x = x.parent
                        end
                    end
                end
                if CSTParser.defines_module(x) && p <= offset <= p + x[1].fullspan + x[2].fullspan
                    x = x.parent
                end

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
    uri = params.textDocument.uri
    hasdocument(server, uri) || return nodocuemnt_error(uri)

    doc = getdocument(server, uri)
    env = getenv(doc, server)
    if get_version(doc) !== params.version
        return mismatched_version_error(uri, doc, params, "getDocAt")
    end

    x = get_expr1(getcst(doc), get_offset(doc, params.position))
    x isa EXPR && CSTParser.isoperator(x) && resolve_op_ref(x, env)
    documentation = get_hover(x, "", server)

    return documentation
end

function _score(needle::Symbol, haystack::Symbol)
    if needle === haystack
        return 0
    end
    needle, haystack = lowercase(string(needle)), lowercase(string(haystack))
    ldist = REPL.levenshtein(needle, haystack)

    if startswith(haystack, needle)
        ldist *= 0.5
    end

    return ldist
end
# TODO: handle documentation resolving properly, respect how Documenter handles that
function julia_getDocFromWord_request(params::NamedTuple{(:word,),Tuple{String}}, server::LanguageServerInstance, conn)
    matches = Pair{Float64, String}[]
    needle = Symbol(params.word)
    nfound = 0
    traverse_by_name(getsymbols(getenv(server))) do sym, val
        # this would ideally use the Damerau-Levenshtein distance or even something fancier:
        score = _score(needle, sym)
        if score < 2
            val = get_hover(val, "", server)
            if !isempty(val)
                nfound += 1
                push!(matches, score => val)
            end
        end
    end
    if isempty(matches)
        return "No results found."
    else
        return join(map(x -> x.second, sort!(unique!(matches), by = x -> x.first)[1:min(end, 25)]), "\n---\n")
    end
end

function textDocument_selectionRange_request(params::SelectionRangeParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    ret = map(params.positions) do position
        offset = get_offset(doc, position)
        x = get_expr1(getcst(doc), offset)
        get_selection_range_of_expr(x)
    end
    return ret isa Vector{SelectionRange} ?
        ret :
        nothing
end

# Just returns a selection for each parent EXPR, should be more selective
get_selection_range_of_expr(x) = missing
function get_selection_range_of_expr(x::EXPR)
    doc, offset = get_file_loc(x)
    l1, c1 = get_position_from_offset(doc, offset)
    l2, c2 = get_position_from_offset(doc, offset + x.span)
    SelectionRange(Range(l1, c1, l2, c2), get_selection_range_of_expr(x.parent))
end
