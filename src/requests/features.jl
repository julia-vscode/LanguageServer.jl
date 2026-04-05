

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

function get_definitions(x, tls, env, locations, server) end # Fallback

function get_definitions(x::SymbolServer.ModuleStore, tls, env, locations, server)
    if haskey(x.vals, :eval) && x[:eval] isa SymbolServer.FunctionStore
        get_definitions(x[:eval], tls, env, locations, server)
    end
end

function get_definitions(x::Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}, tls, env, locations, server)
    StaticLint.iterate_over_ss_methods(x, tls, env, function (m)
        if safe_isfile(m.file)
            push!(locations, Location(filepath2uri(m.file), Range(m.line - 1, 0, m.line - 1, 0)))
        end
        return false
    end)
end

function get_definitions(b::StaticLint.Binding, tls, env, locations, server)
    if !(b.val isa EXPR)
        get_definitions(b.val, tls, env, locations, server)
    end
    if b.type === StaticLint.CoreTypes.Function || b.type === StaticLint.CoreTypes.DataType
        for ref in b.refs
            method = StaticLint.get_method(ref)
            if method !== nothing
                get_definitions(method, tls, env, locations, server)
            end
        end
    elseif b.val isa EXPR
        get_definitions(b.val, tls, env, locations, server)
    end
end

function get_definitions(x::EXPR, tls::StaticLint.Scope, env, locations, server)
    loc = get_file_loc(x, server)
    if loc !== nothing
        uri, o = loc
        push!(locations, Location(uri, jw_range(server, uri, o .+ (0:x.span))))
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
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    meta_dict, env = get_meta_data(server, uri)
    offset = get_offset(st, params.position)
    x = get_expr1(jw_cst(server, uri), offset)
    if x isa EXPR && hasref(x, meta_dict)
        # Replace with own function to retrieve references (with loop saftey-breaker)
        b = refof(x, meta_dict)
        b = resolve_shadow_binding(b)
        (tls = retrieve_toplevel_scope(x, meta_dict)) === nothing && return locations
        get_definitions(b, tls, env, locations, server)
    end

    return unique!(locations)
end

## Old descend/get_file_loc removed — replaced by JW-based get_file_loc(x, server) in staticlint.jl

function search_file(filename, dir, topdir)
    parent_dir = dirname(dir)
    return if (!startswith(dir, topdir) || parent_dir == dir || isempty(dir))
        nothing
    else
        path = joinpath(dir, filename)
        isfile(path) ? path : search_file(filename, parent_dir, topdir)
    end
end

function get_juliaformatter_config(uri, server)
    path = something(uri2filepath(uri), "")

    # search through workspace for a `.JuliaFormatter.toml`
    workspace_dirs = sort(filter(f -> startswith(path, f), collect(server.workspaceFolders)), by = length, rev = true)
    if ismissing(server.initialization_options) || !get(server.initialization_options, INIT_OPT_USE_FORMATTER_CONFIG_DEFAULTS, false)
        config_path = length(workspace_dirs) > 0 ?
                      search_file(JuliaFormatter.CONFIG_FILE_NAME, path, workspace_dirs[1]) :
                      nothing
    else
        @debug "using standard formatter config file locations"
        config_path = length(workspace_dirs) > 0 ?
                      search_file(JuliaFormatter.CONFIG_FILE_NAME, path, "/") :
                      nothing
        if isnothing(config_path) && haskey(ENV, "HOME")
            local home = ENV["HOME"]
            config_path = search_file(JuliaFormatter.CONFIG_FILE_NAME, home, home)
        end
    end

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
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)

    newcontent = try
        config = get_juliaformatter_config(uri, server)
        format_text(st.content, params, config)
    catch err
        return JSONRPC.JSONRPCError(
            -32000,
            "Failed to format document: $err.",
            nothing
        )
    end

    end_l, end_c = get_position_from_offset(st, sizeof(st.content)) # AUDIT: OK
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
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    oldcontent = st.content
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
        config = get_juliaformatter_config(uri, server)
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

function find_references(textDocument::TextDocumentIdentifier, position::Position, server, meta_dict)
    locations = Location[]
    st = jw_source_text(server, textDocument.uri)
    offset = get_offset(st, position)
    x = get_expr1(jw_cst(server, textDocument.uri), offset)
    x === nothing && return locations
    for_each_ref(x, meta_dict, server) do r, uri, o
        push!(locations, Location(uri, jw_range(server, uri, o .+ (0:r.span))))
    end
    return locations
end

function for_each_ref(f, identifier::EXPR, meta_dict, server)
    if identifier isa EXPR && hasref(identifier, meta_dict) && refof(identifier, meta_dict) isa StaticLint.Binding
        for r in loose_refs(refof(identifier, meta_dict), meta_dict)
            if r isa EXPR
                loc = get_file_loc(r, server)
                if loc !== nothing
                    uri, o = loc
                    f(r, uri, o)
                end
            end
        end
    end
end

function textDocument_references_request(params::ReferenceParams, server::LanguageServerInstance, conn)
    meta_dict, _ = get_meta_data(server, params.textDocument.uri)
    return find_references(params.textDocument, params.position, server, meta_dict)
end

function textDocument_rename_request(params::RenameParams, server::LanguageServerInstance, conn)
    tdes = Dict{URI,TextDocumentEdit}()
    meta_dict, _ = get_meta_data(server, params.textDocument.uri)
    locations = find_references(params.textDocument, params.position, server, meta_dict)

    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, params.newName))
        else
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, jw_version(server, loc.uri)), [TextEdit(loc.range, params.newName)])
        end
    end

    return WorkspaceEdit(missing, collect(values(tdes)))
end

function textDocument_prepareRename_request(params::PrepareRenameParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    x = get_expr1(jw_cst(server, uri), get_offset(st, params.position))
    x isa EXPR || return nothing
    loc = get_file_loc(x, server)
    loc === nothing && return nothing
    uri, x_start_offset = loc
    x_range = jw_range(server, uri, x_start_offset .+ (0:x.span))
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
    meta_dict, _ = get_meta_data(server, uri)

    return collect_document_symbols(jw_cst(server, uri), server, uri, meta_dict)
end

struct BindingContext
    is_function_def::Bool
    is_datatype_def::Bool
    is_datatype_def_body::Bool
end
BindingContext() = BindingContext(false, false, false)

function collect_document_symbols(x::EXPR, server::LanguageServerInstance, uri, meta_dict, pos=0, ctx=BindingContext(), symbols=DocumentSymbol[])
    is_datatype_def_body = ctx.is_datatype_def_body
    if ctx.is_datatype_def && !is_datatype_def_body
        is_datatype_def_body = x.head === :block && length(x.parent.args) >= 3 && x.parent.args[3] == x
    end
    ctx = BindingContext(
        ctx.is_function_def || CSTParser.defines_function(x),
        ctx.is_datatype_def || CSTParser.defines_datatype(x),
        is_datatype_def_body,
    )

    if bindingof(x, meta_dict) !== nothing
        b =  bindingof(x, meta_dict)
        if b.val isa EXPR && is_valid_binding_name(b.name)
            ds = DocumentSymbol(
                get_name_of_binding(b.name), # name
                missing, # detail
                _binding_kind(b, ctx), # kind
                false, # deprecated
                jw_range(server, uri, (pos .+ (0:x.span))), # range
                jw_range(server, uri, (pos .+ (0:x.span))), # selection range
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
                        jw_range(server, uri, (pos .+ (0:x.span))), # range
                        jw_range(server, uri, (pos .+ (0:x.span))), # selection range
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
            collect_document_symbols(a, server, uri, meta_dict, pos, ctx, symbols)
            pos += a.fullspan
        end
    end
    return symbols
end

function collect_bindings_w_loc(x::EXPR, meta_dict, pos=0, bindings=Tuple{UnitRange{Int},StaticLint.Binding}[])
    if bindingof(x, meta_dict) !== nothing
        push!(bindings, (pos .+ (0:x.span), bindingof(x, meta_dict)))
    end
    if length(x) > 0
        for a in x
            collect_bindings_w_loc(a, meta_dict, pos, bindings)
            pos += a.fullspan
        end
    end
    return bindings
end

function collect_toplevel_bindings_w_loc(x::EXPR, meta_dict, pos=0, bindings=Tuple{UnitRange{Int},StaticLint.Binding}[]; query="")
    if bindingof(x, meta_dict) isa StaticLint.Binding && valof(bindingof(x, meta_dict).name) isa String && bindingof(x, meta_dict).val isa EXPR && startswith(valof(bindingof(x, meta_dict).name), query)
        push!(bindings, (pos .+ (0:x.span), bindingof(x, meta_dict)))
    end
    if scopeof(x, meta_dict) !== nothing && !(headof(x) === :file || CSTParser.defines_module(x))
        return bindings
    end
    if length(x) > 0
        for a in x
            collect_toplevel_bindings_w_loc(a, meta_dict, pos, bindings, query=query)
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

    if JuliaWorkspaces.has_file(server.workspace, uri)
        if jw_version(server, uri) == params.version
            st = jw_source_text(server, uri)
            offset = index_at(st, params.position, true)
            x, p = get_expr_or_parent(jw_cst(server, uri), offset, 1)
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

                meta_dict, _ = get_meta_data(server, uri)
                scope = retrieve_scope(x, meta_dict)
                if scope !== nothing
                    return get_module_of(scope)
                end
            end
        else
            return mismatched_version_error(uri, jw_version(server, uri), params, "getModuleAt")
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
    JuliaWorkspaces.has_file(server.workspace, uri) || return nodocument_error(uri, "getDocAt")

    st = jw_source_text(server, uri)
    meta_dict, env = get_meta_data(server, uri)
    if jw_version(server, uri) !== params.version
        return mismatched_version_error(uri, jw_version(server, uri), params, "getDocAt")
    end

    x = get_expr1(jw_cst(server, uri), get_offset(st, params.position))
    x isa EXPR && CSTParser.isoperator(x) && resolve_op_ref(x, env, meta_dict)
    documentation = get_hover(x, "", server, x, env, meta_dict)

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
            val = get_hover(val, "", server, nothing, getenv(server), _empty_meta_dict)
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
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    cst = jw_cst(server, uri)
    ret = map(params.positions) do position
        offset = get_offset(st, position)
        x = get_expr1(cst, offset)
        get_selection_range_of_expr(x, server)
    end
    return ret isa Vector{SelectionRange} ?
        ret :
        nothing
end

# Just returns a selection for each parent EXPR, should be more selective
get_selection_range_of_expr(x, server) = missing
function get_selection_range_of_expr(x::EXPR, server)
    loc = get_file_loc(x, server)
    loc === nothing && return missing
    uri, offset = loc
    st = jw_source_text(server, uri)
    l1, c1 = JuliaWorkspaces.position_at(st, offset)
    l2, c2 = JuliaWorkspaces.position_at(st, offset + x.span)
    SelectionRange(Range(l1 - 1, c1 - 1, l2 - 1, c2 - 1), get_selection_range_of_expr(x.parent, server))
end

function textDocument_inlayHint_request(params::InlayHintParams, server::LanguageServerInstance, conn)::Union{Vector{InlayHint},Nothing}
    if !server.inlay_hints
        return nothing
    end

    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    meta_dict, _ = get_meta_data(server, uri)

    start, stop = get_offset(st, params.range.start), get_offset(st, params.range.stop)

    return collect_inlay_hints(jw_cst(server, uri), server, uri, st, meta_dict, start, stop)
end

function get_inlay_parameter_hints(x::EXPR, server::LanguageServerInstance, uri, st, meta_dict, pos=0)
    if server.inlay_hints_parameter_names === :all || (
        server.inlay_hints_parameter_names === :literals &&
        CSTParser.isliteral(x)
    )
        sigs = collect_signatures(x, server, uri, meta_dict)

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
                Position(get_position_from_offset(st, pos)...),
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

function collect_inlay_hints(x::EXPR, server::LanguageServerInstance, uri, st, meta_dict, start, stop, pos=0, hints=InlayHint[])
    if x isa EXPR && parentof(x) isa EXPR &&
            CSTParser.iscall(parentof(x)) &&
            !(
                parentof(parentof(x)) isa EXPR &&
                CSTParser.defines_function(parentof(parentof(x)))
            ) &&
            parentof(x).args[1] != x # function calls
        maybe_hint = get_inlay_parameter_hints(x, server, uri, st, meta_dict, pos)
        if maybe_hint !== nothing
            push!(hints, maybe_hint)
        end
    elseif x isa EXPR && parentof(x) isa EXPR &&
            CSTParser.isassignment(parentof(x)) &&
            parentof(x).args[1] == x &&
            hasbinding(x, meta_dict) # assignment
        if server.inlay_hints_variable_types
            typ = _completion_type(bindingof(x, meta_dict))
            if typ !== missing
                push!(
                    hints,
                    InlayHint(
                        Position(get_position_from_offset(st, pos + x.span)...),
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
                collect_inlay_hints(a, server, uri, st, meta_dict, start, stop, pos, hints)
            end
            pos += a.fullspan
            pos > stop && break
        end
    end
    return hints
end
