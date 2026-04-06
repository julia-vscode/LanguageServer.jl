

function textDocument_definition_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    results = JuliaWorkspaces.get_definitions(server.workspace, uri, index)

    locations = map(results) do r
        Location(r.uri, jw_range(server, r.uri, r.start, r.stop))
    end

    return unique!(locations)
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

function textDocument_references_request(params::ReferenceParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    results = JuliaWorkspaces.get_references(server.workspace, uri, index)

    return map(results) do r
        Location(r.uri, jw_range(server, r.uri, r.start, r.stop))
    end
end

function textDocument_rename_request(params::RenameParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    edits = JuliaWorkspaces.get_rename_edits(server.workspace, uri, index, params.newName)
    isempty(edits) && return WorkspaceEdit(missing, TextDocumentEdit[])

    tdes = Dict{URI,TextDocumentEdit}()
    for e in edits
        if !haskey(tdes, e.uri)
            tdes[e.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(e.uri, jw_version(server, e.uri)), TextEdit[])
        end
        push!(tdes[e.uri].edits, TextEdit(jw_range(server, e.uri, e.start, e.stop), e.new_text))
    end

    return WorkspaceEdit(missing, collect(values(tdes)))
end

function textDocument_prepareRename_request(params::PrepareRenameParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    result = JuliaWorkspaces.can_rename(server.workspace, uri, index)
    result === nothing && return nothing

    return jw_range(server, uri, result.start, result.stop)
end

function textDocument_documentSymbol_request(params::DocumentSymbolParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    results = JuliaWorkspaces.get_document_symbols(server.workspace, uri)

    function convert_symbol(r::JuliaWorkspaces.DocumentSymbolResult)
        children = DocumentSymbol[convert_symbol(c) for c in r.children]
        rng = jw_range(server, uri, r.start, r.stop)
        DocumentSymbol(r.name, missing, r.kind, false, rng, rng, children)
    end

    return DocumentSymbol[convert_symbol(r) for r in results]
end

function julia_getModuleAt_request(params::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri

    if JuliaWorkspaces.has_file(server.workspace, uri)
        if jw_version(server, uri) == params.version
            st = jw_source_text(server, uri)
            index = index_at(st, params.position, true)
            result = JuliaWorkspaces.get_module_at(server.workspace, uri, index)
            return result === nothing ? "Main" : result
        else
            return mismatched_version_error(uri, jw_version(server, uri), params, "getModuleAt")
        end
    else
        return nodocument_error(uri, "getModuleAt")
    end
end

function julia_getDocAt_request(params::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    JuliaWorkspaces.has_file(server.workspace, uri) || return nodocument_error(uri, "getDocAt")

    st = jw_source_text(server, uri)
    if jw_version(server, uri) !== params.version
        return mismatched_version_error(uri, jw_version(server, uri), params, "getDocAt")
    end

    index = index_at(st, params.position)
    documentation = JuliaWorkspaces.get_hover_text(server.workspace, uri, index)

    return documentation === nothing ? "" : documentation
end

# TODO: handle documentation resolving properly, respect how Documenter handles that
function julia_getDocFromWord_request(params::NamedTuple{(:word,),Tuple{String}}, server::LanguageServerInstance, conn)
    return JuliaWorkspaces.get_doc_from_word(server.workspace, params.word)
end

function textDocument_selectionRange_request(params::SelectionRangeParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)

    indices = [index_at(st, p) for p in params.positions]
    results = JuliaWorkspaces.get_selection_ranges(server.workspace, uri, indices)

    function convert_selection(r::Union{Nothing, JuliaWorkspaces.SelectionRangeResult})
        r === nothing && return missing
        parent = convert_selection(r.parent)
        SelectionRange(jw_range(server, uri, r.start, r.stop), parent)
    end

    ret = SelectionRange[convert_selection(r) for r in results]
    return isempty(ret) ? nothing : ret
end

function textDocument_inlayHint_request(params::InlayHintParams, server::LanguageServerInstance, conn)::Union{Vector{InlayHint},Nothing}
    if !server.inlay_hints
        return nothing
    end

    uri = params.textDocument.uri
    st = jw_source_text(server, uri)

    start_index = index_at(st, params.range.start)
    end_index = index_at(st, params.range.stop)

    config = JuliaWorkspaces.InlayHintConfig(
        server.inlay_hints,
        server.inlay_hints_variable_types,
        server.inlay_hints_parameter_names
    )

    results = JuliaWorkspaces.get_inlay_hints(server.workspace, uri, start_index, end_index, config)
    isempty(results) && return nothing

    return map(results) do r
        kind = r.kind === :parameter ? InlayHintKinds.Parameter : InlayHintKinds.Type
        InlayHint(
            jw_position_to_lsp(server, uri, r.position),
            r.label,
            kind,
            missing,
            missing,
            r.padding_left,
            r.padding_right,
            missing
        )
    end
end
