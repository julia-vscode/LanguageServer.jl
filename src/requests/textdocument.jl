function textDocument_didOpen_notification(params::DidOpenTextDocumentParams, server::LanguageServerInstance, conn)
    JuliaWorkspaces.mark_current_diagnostics(server.workspace)
    JuliaWorkspaces.mark_current_testitems(server.workspace)

    uri = params.textDocument.uri
    if hasdocument(server, uri)
        doc = getdocument(server, uri)
        set_text_document!(doc, TextDocument(uri, params.textDocument.text, params.textDocument.version, params.textDocument.languageId))
        set_open_in_editor(doc, true)
    else
        doc = Document(TextDocument(uri, params.textDocument.text, params.textDocument.version, params.textDocument.languageId), false, server)
        setdocument!(server, uri, doc)
        doc._workspace_file = any(i -> startswith(string(uri), string(filepath2uri(i))), server.workspaceFolders)
        set_open_in_editor(doc, true)

        fpath = getpath(doc)

        !isempty(fpath) && try_to_load_parents(fpath, server)
    end

    if haskey(server._open_file_versions, uri)
        error("This should not happen")
    end

    new_text_file = JuliaWorkspaces.TextFile(uri, JuliaWorkspaces.SourceText(params.textDocument.text, params.textDocument.languageId))

    if haskey(server._files_from_disc, uri)
        JuliaWorkspaces.update_file!(server.workspace, new_text_file)
    else
        JuliaWorkspaces.add_file!(server.workspace, new_text_file)
    end
    server._open_file_versions[uri] = params.textDocument.version

    parse_all(doc, server)
    lint!(doc, server)
    publish_diagnostics([get_uri(doc)], server, conn, "textDocument_didOpen_notification")
    publish_tests(server)
end


function textDocument_didClose_notification(params::DidCloseTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    doc = getdocument(server, uri)

    JuliaWorkspaces.mark_current_testitems(server.workspace)

    if is_workspace_file(doc)
        set_open_in_editor(doc, false)
    else
        if any(getroot(d) == getroot(doc) && (d._open_in_editor || is_workspace_file(d)) for (uri, d::Document) in getdocuments_pair(server) if d != doc)
            # If any other open document shares doc's root we just mark it as closed...
            set_open_in_editor(doc, false)
        else
            # ...otherwise we delete all documents that share root with doc.
            for (u, d) in getdocuments_pair(server)
                if getroot(d) == getroot(doc)
                    deletedocument!(server, u)
                    empty!(doc.diagnostics)
                    # publish_diagnostics(Document[doc], server, conn)
                end
            end
        end
    end

    if !haskey(server._open_file_versions, uri)
        error("This should not happen")
    end
    delete!(server._open_file_versions, uri)

    # If the file exists on disc, we go back to that version
    if haskey(server._files_from_disc, uri)
        JuliaWorkspaces.update_file!(server.workspace, server._files_from_disc[uri])
    else
        JuliaWorkspaces.remove_file!(server.workspace, uri)
    end

    publish_tests(server)
end

function textDocument_didSave_notification(params::DidSaveTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    doc = getdocument(server, uri)
    if params.text isa String
        if get_text(doc) != params.text
            println(stderr, "Mismatch between server and client text")
            println(stderr, "========== BEGIN SERVER SIDE TEXT ==========")
            println(stderr, get_text(doc))
            println(stderr, "========== END SERVER SIDE TEXT ==========")
            println(stderr, "========== BEGIN CLIENT SIDE TEXT ==========")
            println(stderr, params.text)
            println(stderr, "========== END CLIENT SIDE TEXT ==========")
            JSONRPC.send(conn, window_showMessage_notification_type, ShowMessageParams(MessageTypes.Error, "Julia Extension: Please contact us! Your extension just crashed with a bug that we have been trying to replicate for a long time. You could help the development team a lot by contacting us at https://github.com/julia-vscode/julia-vscode so that we can work together to fix this issue."))
            throw(LSSyncMismatch("Mismatch between server and client text for $(get_uri(doc)). _open_in_editor is $(doc._open_in_editor). _workspace_file is $(doc._workspace_file). _version is $(get_version(doc))."))
        end
    end
    # parse_all(doc, server)
end

function textDocument_willSave_notification(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
end

function textDocument_willSaveWaitUntil_request(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
    return TextEdit[]
end

comp(x, y) = x == y
function comp(x::CSTParser.EXPR, y::CSTParser.EXPR)
    comp(x.head, y.head) &&
    x.span == y.span &&
    x.fullspan == y.fullspan &&
    x.val == y.val &&
    length(x) == length(y) &&
    all(comp(x[i], y[i]) for i = 1:length(x))
end

function measure_sub_operation(f, request_name, server)
    start_time = string(Dates.unix2datetime(time()), "Z")
    tic = time_ns()
    res = f()
    toc = time_ns()
    duration = (toc - tic) / 1e+6

    JSONRPC.send(
        server.jr_endpoint,
        telemetry_event_notification_type,
        Dict(
            "command" => "request_metric",
            "operationId" => string(uuid4()),
            "operationParentId" => g_operationId[],
            "name" => request_name,
            "duration" => duration,
            "time" => start_time
        )
    )

    return res
end

function textDocument_didChange_notification(params::DidChangeTextDocumentParams, server::LanguageServerInstance, conn)
    JuliaWorkspaces.mark_current_diagnostics(server.workspace)
    JuliaWorkspaces.mark_current_testitems(server.workspace)

    uri = params.textDocument.uri

    doc = getdocument(server, params.textDocument.uri)

    s0 = get_text(doc)

    if params.textDocument.version < get_version(doc)
        error("The client and server have different textDocument versions for $(get_uri(doc)). LS version is $(get_version(doc)), request version is $(params.textDocument.version).")
    end

    new_text_document = apply_text_edits(get_text_document(doc), params.contentChanges, params.textDocument.version)
    set_text_document!(doc, new_text_document)

    if !haskey(server._open_file_versions, uri)
        error("This should not happen")
    end

    if server._open_file_versions[uri]>params.textDocument.version
        error("Outdated version: server $(server._open_file_versions[uri]) params $(params.textDocument.version)")
    end

    # We originally applied each text edit individually, but that doesn't work because
    # we need to convert the LS positions to Julia indices after each text edit update
    # For now we just use the new text that we already created for the legacy TextDocument
    new_text_file = JuliaWorkspaces.TextFile(uri, JuliaWorkspaces.SourceText(get_text(new_text_document), get_language_id(doc)))
    JuliaWorkspaces.update_file!(server.workspace, new_text_file)

    if get_language_id(doc) in ("markdown", "juliamarkdown")
        parse_all(doc, server)
        lint!(doc, server)
    elseif get_language_id(doc) == "julia"
        cst0, cst1 = getcst(doc), CSTParser.parse(get_text(doc), true)
        r1, r2, r3 = CSTParser.minimal_reparse(s0, get_text(doc), cst0, cst1, inds = true)
        for i in setdiff(1:length(cst0.args), r1 , r3) # clean meta from deleted expr
            StaticLint.clear_meta(cst0[i])
        end
        setcst(doc, EXPR(cst0.head, EXPR[cst0.args[r1]; cst1.args[r2]; cst0.args[r3]], nothing))
        sizeof(get_text(doc)) == getcst(doc).fullspan || @error "CST does not match input string length."
        headof(doc.cst) === :file ? set_doc(doc.cst, doc) : @info "headof(doc) isn't :file for $(doc._path)"

        target_exprs = getcst(doc).args[last(r1) .+ (1:length(r2))]

        semantic_pass(getroot(doc), target_exprs)
        lint!(doc, server)
    end

    publish_diagnostics([get_uri(doc)], server, conn, "textDocument_didChange_notification")
    publish_tests(server)
end

function parse_all(doc::Document, server::LanguageServerInstance)
    StaticLint.clear_meta(getcst(doc))
    if get_language_id(doc) in ("markdown", "juliamarkdown")
        doc.cst, ps = parse_jmd(get_text(doc))
    elseif get_language_id(doc) == "julia"
        t = @elapsed begin
            ps = CSTParser.ParseState(get_text(doc))
            doc.cst, ps = CSTParser.parse(ps, true)
        end
        if t > 1
            # warn to help debugging in the wild
            @warn "CSTParser took a long time ($(round(Int, t)) seconds) to parse $(repr(getpath(doc)))"
        end
    else
        return
    end
    sizeof(get_text(doc)) == getcst(doc).fullspan || @error "CST does not match input string length."
    if headof(doc.cst) === :file
        set_doc(doc.cst, doc)
    end
    semantic_pass(getroot(doc))
end

function mark_errors(doc, out=Diagnostic[])
    line_offsets = get_line_offsets(get_text_document(doc))
    # Extend line_offsets by one to consider up to EOF
    line_offsets = vcat(line_offsets, length(get_text(doc)) + 1)
    errs = StaticLint.collect_hints(getcst(doc), getenv(doc), doc.server.lint_missingrefs)
    n = length(errs)
    n == 0 && return out
    i = 1
    start = true
    offset = errs[i][1]
    r = Int[0, 0]
    nlines = length(line_offsets)
    if offset > last(line_offsets)
        line = nlines
    else
        line = 1
        io = IOBuffer(get_text(doc))
        while line < nlines
            seek(io, line_offsets[line])
            char = 0
            while line_offsets[line] <= offset < line_offsets[line + 1]
                while offset > position(io)
                    c = read(io, Char)
                    if UInt32(c) >= 0x010000
                        char += 1
                    end
                    char += 1
                end
                if start
                    r[1] = line
                    r[2] = char
                    offset += errs[i][2].span
                else
                    rng = Range(r[1] - 1, r[2], line - 1, char)
                    if headof(errs[i][2]) === :errortoken
                        # push!(out, Diagnostic(rng, DiagnosticSeverities.Error, missing, missing, "Julia", "Parsing error", missing, missing))
                    elseif CSTParser.isidentifier(errs[i][2]) && !StaticLint.haserror(errs[i][2])
                        push!(out, Diagnostic(rng, DiagnosticSeverities.Warning, missing, missing, "Julia", "Missing reference: $(errs[i][2].val)", missing, missing))
                    elseif StaticLint.haserror(errs[i][2]) && StaticLint.errorof(errs[i][2]) isa StaticLint.LintCodes
                        code = StaticLint.errorof(errs[i][2])
                        description = get(StaticLint.LintCodeDescriptions, code, "")
                        severity, tags = if code in (StaticLint.UnusedFunctionArgument, StaticLint.UnusedBinding, StaticLint.UnusedTypeParameter)
                            DiagnosticSeverities.Hint, [DiagnosticTags.Unnecessary]
                        else
                            DiagnosticSeverities.Information, missing
                        end
                        code_details = if isdefined(StaticLint, :IndexFromLength) && code === StaticLint.IndexFromLength
                            CodeDescription(URI("https://docs.julialang.org/en/v1/base/arrays/#Base.eachindex"))
                        else
                            missing
                        end
                        push!(out, Diagnostic(rng, severity, string(code), code_details, "Julia", description, tags, missing))
                    end
                    i += 1
                    i > n && break
                    offset = errs[i][1]
                end
                start = !start
                offset = start ? errs[i][1] : errs[i][1] + errs[i][2].span
            end
            line += 1
        end
        close(io)
    end
    return out
end

isunsavedfile(doc::Document) = get_uri(doc).scheme == "untitled" # Not clear if this is consistent across editors.

"""
is_diag_dependent_on_env(diag::Diagnostic)::Bool

Is this diagnostic reliant on the current environment being accurately represented?
"""
function is_diag_dependent_on_env(diag::Diagnostic)
    startswith(diag.message, "Missing reference: ") ||
    startswith(diag.message, "Possible method call error") ||
    startswith(diag.message, "An imported")
end

function print_substitute_line(io::IO, line)
    if endswith(line, '\n')
        println(io, ' '^(sizeof(line) - 1))
    else
        print(io, ' '^sizeof(line))
    end
end

function parse_jmd(str)
    cleaned = IOBuffer()
    in_julia_block = false
    for line in eachline(IOBuffer(str), keep=true)
        if startswith(line, r"^```({?julia|@example|@setup)")
            in_julia_block = true
            print_substitute_line(cleaned, line)
            continue
        elseif startswith(line, r"\s*```")
            in_julia_block = false
        end
        if in_julia_block
            print(cleaned, line)
        else
            print_substitute_line(cleaned, line)
        end
    end

    ps = CSTParser.ParseState(String(take!(cleaned)))
    return CSTParser.parse(ps, true)
end

function search_for_parent(dir::String, file::String, drop=3, parents=String[])
    drop < 1 && return parents
    try
        !isdir(dir) && return parents
        !hasreadperm(dir) && return parents
        for f in readdir(dir)
            filename = joinpath(dir, f)
            if isvalidjlfile(filename)
                # Could be sped up?
                content = try
                    s = read(filename, String)
                    our_isvalid(s) || continue
                    s
                catch err
                    isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
                    continue
                end
                occursin(file, content) && push!(parents, joinpath(dir, f))
            end
        end
        search_for_parent(splitdir(dir)[1], file, drop - 1, parents)
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return parents
    end

    return parents
end


function is_parentof(parent_path, child_path, server)
    !isvalidjlfile(parent_path) && return false
    previous_server_docs = collect(getdocuments_key(server)) # additions to this to be removed at end
    # load parent file
    puri = filepath2uri(parent_path)
    if !hasdocument(server, puri)
        content = try
            s = read(parent_path, String)
            our_isvalid(s) || return false
            s
        catch err
            isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
            return false
        end
        pdoc = Document(TextDocument(puri, content, 0), false, server)
        setdocument!(server, puri, pdoc)
        CSTParser.parse(get_text(pdoc), true)
        if headof(pdoc.cst) === :file
            set_doc(pdoc.cst, pdoc)
        end
    else
        pdoc = getdocument(server, puri)
    end
    semantic_pass(getroot(pdoc))
    # check whether child has been included automatically
    if any(getpath(d) == child_path for (k, d) in getdocuments_pair(server) if !(k in previous_server_docs))
        cdoc = getdocument(server, filepath2uri(child_path))
        parse_all(cdoc, server)
        return true, "", CSTParser.Tokens.STRING
    else
        # clean up
        foreach(k -> !(k in previous_server_docs) && deletedocument!(server, k), getdocuments_key(server))
        return false
    end
end

function try_to_load_parents(child_path, server)
    for p in search_for_parent(splitdir(child_path)...)
        p == child_path && continue
        success = is_parentof(p, child_path, server)
        if success
            return try_to_load_parents(p, server)
        end
    end
end

function publish_diagnostics(uris::Vector{URI}, server, conn, source)
    JuliaWorkspaces.get_files_with_updated_diagnostics(server.workspace)

    all_uris_with_updates = Set{URI}()

    for uri in uris
        push!(all_uris_with_updates, uri)
    end

    for uri in jw_diagnostics_updated
        push!(all_uris_with_updates, uri)
    end

    diagnostics = Dict{URI,Vector{Diagnostic}}()

    for uri in all_uris_with_updates
        diags = Diagnostic[]
        diagnostics[uri] = diags

        if hasdocument(server, uri)
            doc = getdocument(server, uri)

            if server.runlinter && (is_workspace_file(doc) || isunsavedfile(doc))
                pkgpath = getpath(doc)
                if any(is_in_target_dir_of_package.(Ref(pkgpath), server.lint_disableddirs))
                    filter!(!is_diag_dependent_on_env, doc.diagnostics)
                end
                append!(diags, doc.diagnostics)
            end
        end

        if JuliaWorkspaces.has_file(server.workspace, uri)
            st = JuliaWorkspaces.get_text_file(server.workspace, uri).content

            JuliaWorkspaces.get_diagnostic(server.workspace, uri)

            append!(diags, Diagnostic(
                Range(st, i.range),
                if i.severity==:error
                    DiagnosticSeverities.Error
                elseif i.severity==:warning
                    DiagnosticSeverities.Warning
                elseif i.severity==:info
                    DiagnosticSeverities.Information
                else
                    error("Unknown severity $(i.severity)")
                end,
                missing,
                missing,
                i.source,
                i.message,
                missing,
                missing
            ) for i in new_diags)
        end
    end

    for (uri,diags) in diagnostics
        version = get(server._open_file_versions, uri, missing)
        params = PublishDiagnosticsParams(uri, version, diags)
        JSONRPC.send(conn, textDocument_publishDiagnostics_notification_type, params)
    end
end

function publish_tests(server::LanguageServerInstance)
    if !ismissing(server.initialization_options) && get(server.initialization_options, "julialangTestItemIdentification", false)
        updated_files, deleted_files = JuliaWorkspaces.get_files_with_updated_testitems(server.workspace)

        for uri in updated_files
            testitems_results = JuliaWorkspaces.get_test_items(server.workspace, uri)
            st = JuliaWorkspaces.get_text_file(server.workspace, uri).content

            testitems = TestItemDetail[TestItemDetail(i.id, i.name, Range(st, i.range), st.content[i.code_range], Range(st, i.code_range), i.option_default_imports, string.(i.option_tags), string.(i.option_setup)) for i in testitems_results.testitems]
            testsetups= TestSetupDetail[TestSetupDetail(string(i.name), string(i.kind), Range(st, i.range), st.content[i.code_range], Range(st, i.code_range), ) for i in testitems_results.testsetups]
            testerrors = TestErrorDetail[TestErrorDetail(te.id, te.name, Range(st, te.range), te.message) for te in testitems_results.testerrors]

            version = get(server._open_file_versions, uri, missing)

            params = PublishTestsParams(
                uri,
                version,
                testitems,
                testsetups,
                testerrors
            )
            JSONRPC.send(server.jr_endpoint, textDocument_publishTests_notification_type, params)
        end

        for uri in deleted_files
            JSONRPC.send(server.jr_endpoint, textDocument_publishTests_notification_type, PublishTestsParams(uri, missing, TestItemDetail[], TestSetupDetail[], TestErrorDetail[]))
        end
    end
end
