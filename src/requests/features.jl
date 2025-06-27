

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

    return unique!(locations)
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
    return (;
        JuliaFormatter.options(JuliaFormatter.MinimalStyle())...,
        indent = params.options.tabSize,
    )
end

function textDocument_formatting_request(params::DocumentFormattingParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)

    newcontent = try
        config = get_juliaformatter_config(doc, server)
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

# Strings broken up and joined with * to make this file formattable
const FORMAT_MARK_BEGIN = "---- BEGIN LANGUAGESERVER" * " RANGE FORMATTING ----"
const FORMAT_MARK_END = "---- END LANGUAGESERVER" * " RANGE FORMATTING ----"

function textDocument_range_formatting_request(params::DocumentRangeFormattingParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    oldcontent = get_text(doc)
    startline = params.range.start.line + 1
    stopline = params.range.stop.line + 1

    # Insert start and stop line comments as markers in the original text
    original_lines = collect(eachline(IOBuffer(oldcontent); keep=true))
    stopline = min(stopline, length(original_lines))
    original_block = join(@view(original_lines[startline:stopline]))
    # If the stopline do not have a trailing newline we need to add that before our stop
    # comment marker. This is removed after formatting.
    stopline_has_newline = original_lines[stopline] != chomp(original_lines[stopline])
    insert!(original_lines, stopline + 1, (stopline_has_newline ? "# " : "\n# ") * FORMAT_MARK_END * "\n")
    insert!(original_lines, startline, "# " * FORMAT_MARK_BEGIN * "\n")
    text_marked = join(original_lines)

    # Format the full marked text
    text_formatted = try
        config = get_juliaformatter_config(doc, server)
        format_text(text_marked, params, config)
    catch err
        return JSONRPC.JSONRPCError(
            -33000,
            "Failed to format document: $err.",
            nothing
        )
    end

    # Find the markers in the formatted text and extract the lines in between
    formatted_lines = collect(eachline(IOBuffer(text_formatted); keep=true))
    start_idx = findfirst(x -> occursin(FORMAT_MARK_BEGIN, x), formatted_lines)
    start_idx === nothing && return TextEdit[]
    stop_idx = findfirst(x -> occursin(FORMAT_MARK_END, x), formatted_lines)
    stop_idx === nothing && return TextEdit[]
    formatted_block = join(@view(formatted_lines[(start_idx+1):(stop_idx-1)]))

    # Remove the extra inserted newline if there was none from the start
    if !stopline_has_newline
        formatted_block = chomp(formatted_block)
    end

    # Don't suggest an edit in case the formatted text is identical to original text
    if formatted_block == original_block
        return TextEdit[]
    end

    # End position is exclusive, replace until start of next line
    return TextEdit[TextEdit(Range(params.range.start.line, 0, params.range.stop.line + 1, 0), formatted_block)]
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
        for r in StaticLint.loose_refs(refof(identifier))
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

struct BindingContext
    is_function_def::Bool
    is_datatype_def::Bool
    is_datatype_def_body::Bool
end
BindingContext() = BindingContext(false, false, false)

function collect_document_symbols(x::EXPR, server::LanguageServerInstance, doc, pos=0, ctx=BindingContext(), symbols=DocumentSymbol[])
    is_datatype_def_body = ctx.is_datatype_def_body
    if ctx.is_datatype_def && !is_datatype_def_body
        is_datatype_def_body = x.head === :block && length(x.parent.args) >= 3 && x.parent.args[3] == x
    end
    ctx = BindingContext(
        ctx.is_function_def || CSTParser.defines_function(x),
        ctx.is_datatype_def || CSTParser.defines_datatype(x),
        is_datatype_def_body,
    )

    if bindingof(x) !== nothing
        b =  bindingof(x)
        if b.val isa EXPR && is_valid_binding_name(b.name)
            ds = DocumentSymbol(
                get_name_of_binding(b.name), # name
                missing, # detail
                _binding_kind(b, ctx), # kind
                false, # deprecated
                Range(doc, (pos .+ (0:x.span))), # range
                Range(doc, (pos .+ (0:x.span))), # selection range
                DocumentSymbol[] # children
            )
            push!(symbols, ds)
            symbols = ds.children
        end
    elseif x.head == :macrocall
        # detect @testitem/testset "testname" ...
        child_nodes = filter(i -> !(isa(i, EXPR) && i.head == :NOTHING && i.args === nothing), x.args)
        if length(child_nodes) > 1
            macroname = CSTParser.valof(child_nodes[1])
            if macroname == "@testitem" || macroname == "@testset"
                if (child_nodes[2] isa EXPR && child_nodes[2].head == :STRING)
                    testname = CSTParser.valof(child_nodes[2])
                    ds = DocumentSymbol(
                        "$(macroname) \"$(testname)\"", # name
                        missing, # detail
                        3, # kind (namespace)
                        false, # deprecated
                        Range(doc, (pos .+ (0:x.span))), # range
                        Range(doc, (pos .+ (0:x.span))), # selection range
                        DocumentSymbol[] # children
                    )
                    push!(symbols, ds)
                    symbols = ds.children
                end
            end
        end
    end
    if length(x) > 0
        for a in x
            collect_document_symbols(a, server, doc, pos, ctx, symbols)
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

function _binding_kind(b, ctx::BindingContext)
    if b isa StaticLint.Binding
        if b.type === nothing
            if ctx.is_datatype_def_body && !ctx.is_function_def
                return 8
            elseif ctx.is_datatype_def
                return 26
            else
                return 13
            end
        elseif b.type == StaticLint.CoreTypes.Module
            return 2
        elseif b.type == StaticLint.CoreTypes.Function
            return 12
        elseif b.type == StaticLint.CoreTypes.String
            return 15
        elseif b.type == StaticLint.CoreTypes.Int || b.type == StaticLint.CoreTypes.Float64
            return 16
        elseif b.type == StaticLint.CoreTypes.DataType
            if ctx.is_datatype_def && !ctx.is_datatype_def_body
                return 23
            else
                return 26
            end
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
        return nodocument_error(uri, "getModuleAt")
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
    hasdocument(server, uri) || return nodocument_error(uri, "getDocAt")

    doc = getdocument(server, uri)
    env = getenv(doc, server)
    if get_version(doc) !== params.version
        return mismatched_version_error(uri, doc, params, "getDocAt")
    end

    x = get_expr1(getcst(doc), get_offset(doc, params.position))
    x isa EXPR && CSTParser.isoperator(x) && resolve_op_ref(x, env)
    documentation = get_hover(x, "", server, x, env)

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
            val = get_hover(val, "", server, nothing, getenv(server))
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

function textDocument_inlayHint_request(params::InlayHintParams, server::LanguageServerInstance, conn)::Union{Vector{InlayHint},Nothing}
    if !server.inlay_hints
        return nothing
    end

    doc = getdocument(server, params.textDocument.uri)

    start, stop = get_offset(doc, params.range.start), get_offset(doc, params.range.stop)

    return collect_inlay_hints(getcst(doc), server, doc, start, stop)
end

function get_inlay_parameter_hints(x::EXPR, server::LanguageServerInstance, doc, pos=0)
    if server.inlay_hints_parameter_names === :all || (
        server.inlay_hints_parameter_names === :literals &&
        CSTParser.isliteral(x)
    )
        sigs = collect_signatures(x, doc, server)

        nargs = length(parentof(x).args) - 1
        nargs < 2 && return nothing

        filter!(s -> length(s.parameters) == nargs, sigs)
        isempty(sigs) && return nothing

        pars = first(sigs).parameters
        thisarg = 0
        for a in parentof(x).args
            if x == a
                break
            end
            thisarg += 1
        end
        if thisarg <= nargs && thisarg <= length(pars)
            label = pars[thisarg].label
            label == "#unused#" && return nothing
            length(label) <= 2 && return nothing
            CSTParser.str_value(x) == label && return nothing
            x.head == :parameters && return nothing
            if x.head isa CSTParser.EXPR && x.head.head == :OPERATOR && x.head.val == "."
                if x.args[end] isa CSTParser.EXPR && x.args[end].args[end] isa CSTParser.EXPR
                    x.args[end].args[end].val == label && return nothing
                end
            end

            return InlayHint(
                Position(get_position_from_offset(doc, pos)...),
                string(label, "="),
                InlayHintKinds.Parameter,
                missing,
                pars[thisarg].documentation,
                false,
                false,
                missing
            )
        end
    end
    return nothing
end

function collect_inlay_hints(x::EXPR, server::LanguageServerInstance, doc, start, stop, pos=0, hints=InlayHint[])
    if x isa EXPR && parentof(x) isa EXPR &&
            CSTParser.iscall(parentof(x)) &&
            !(
                parentof(parentof(x)) isa EXPR &&
                CSTParser.defines_function(parentof(parentof(x)))
            ) &&
            parentof(x).args[1] != x # function calls
        maybe_hint = get_inlay_parameter_hints(x, server, doc, pos)
        if maybe_hint !== nothing
            push!(hints, maybe_hint)
        end
    elseif x isa EXPR && parentof(x) isa EXPR &&
            CSTParser.isassignment(parentof(x)) &&
            parentof(x).args[1] == x &&
            StaticLint.hasbinding(x) # assignment
        if server.inlay_hints_variable_types
            typ = _completion_type(StaticLint.bindingof(x))
            if typ !== missing
                push!(
                    hints,
                    InlayHint(
                        Position(get_position_from_offset(doc, pos + x.span)...),
                        string("::", typ),
                        InlayHintKinds.Type,
                        missing,
                        missing,
                        missing,
                        missing,
                        missing
                    )
                )
            end
        end
    end
    if length(x) > 0
        for a in x
            if pos < stop && pos + a.fullspan > start
                collect_inlay_hints(a, server, doc, start, stop, pos, hints)
            end
            pos += a.fullspan
            pos > stop && break
        end
    end
    return hints
end
