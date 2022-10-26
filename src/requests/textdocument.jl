function textDocument_didOpen_notification(params::DidOpenTextDocumentParams, server::LanguageServerInstance, conn)
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
    parse_all(doc, server)
end


function textDocument_didClose_notification(params::DidCloseTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    doc = getdocument(server, uri)

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
                    publish_diagnostics(doc, server, conn)
                end
            end
        end
    end
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
    parse_all(doc, server)
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

function textDocument_didChange_notification(params::DidChangeTextDocumentParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)

    s0 = get_text(doc)

    if params.textDocument.version < get_version(doc)
        error("The client and server have different textDocument versions for $(get_uri(doc)). LS version is $(get_version(doc)), request version is $(params.textDocument.version).")
    end

    new_text_document = apply_text_edits(get_text_document(doc), params.contentChanges, params.textDocument.version)
    set_text_document!(doc, new_text_document)

    if get_language_id(doc) in ("markdown", "juliamarkdown")
        parse_all(doc, server)
    else
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
end

function parse_all(doc::Document, server::LanguageServerInstance)
    StaticLint.clear_meta(getcst(doc))
    if get_language_id(doc) in ("markdown", "juliamarkdown")
        doc.cst, ps = parse_jmd(get_text(doc))
    elseif get_language_id(doc) == "julia"
        ps = CSTParser.ParseState(get_text(doc))
        doc.cst, ps = CSTParser.parse(ps, true)
    end
    sizeof(get_text(doc)) == getcst(doc).fullspan || @error "CST does not match input string length."
    if headof(doc.cst) === :file
        set_doc(doc.cst, doc)
    end
    semantic_pass(getroot(doc))

    lint!(doc, server)
end

function mark_errors(doc, out=Diagnostic[])
    line_offsets = get_line_offsets(get_text_document(doc))
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
                        push!(out, Diagnostic(rng, DiagnosticSeverities.Error, missing, missing, "Julia", "Parsing error", missing, missing))
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


function publish_diagnostics(doc::Document, server, conn)
    diagnostics = if server.runlinter && server.symbol_store_ready && (is_workspace_file(doc) || isunsavedfile(doc))
        pkgpath = getpath(doc)
        if any(is_in_target_dir_of_package.(Ref(pkgpath), server.lint_disableddirs))
            filter!(!is_diag_dependent_on_env, doc.diagnostics)
        end
        doc.diagnostics
    else
        Diagnostic[]
    end
    text_document = get_text_document(doc)
    params = PublishDiagnosticsParams(get_uri(text_document), get_version(text_document), diagnostics)
    JSONRPC.send(conn, textDocument_publishDiagnostics_notification_type, params)
end

function clear_diagnostics(uri::URI, server, conn)
    doc = getdocument(server, uri)
    empty!(doc.diagnostics)
    publishDiagnosticsParams = PublishDiagnosticsParams(get_uri(doc), get_version(doc), Diagnostic[])
    JSONRPC.send(conn, textDocument_publishDiagnostics_notification_type, publishDiagnosticsParams)
end

function clear_diagnostics(server, conn)
    for uri in getdocuments_key(server)
        clear_diagnostics(uri, server, conn)
    end
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
        if startswith(line, r"\s*```julia") || startswith(line, r"\s*```{julia")
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
        semantic_pass(getroot(cdoc))
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



function vec_startswith(a, b)
    if length(a) < length(b)
        return false
    end

    for (i,v) in enumerate(b)
        if a[i] != v
            return false
        end
    end
    return true
end

function find_package_for_file(jw::JuliaWorkspace, file::URI)
    file_path = uri2filepath(file)
    package = jw._packages |>
        keys |>
        collect |>
        x -> map(x) do i
            package_folder_path = uri2filepath(i)
            parts = splitpath(package_folder_path)
            return (uri = i, parts = parts)
        end |>
        x -> filter(x) do i
            return vec_startswith(splitpath(file_path), i.parts)
        end |>
        x -> sort(x, by=i->length(i.parts), rev=true) |>
        x -> length(x) == 0 ? nothing : first(x).uri

    return package
end

function find_project_for_file(jw::JuliaWorkspace, file::URI)
    file_path = uri2filepath(file)
    project = jw._projects |>
        keys |>
        collect |>
        x -> map(x) do i
            project_folder_path = uri2filepath(i)
            parts = splitpath(project_folder_path)
            return (uri = i, parts = parts)
        end |>
        x -> filter(x) do i
            return vec_startswith(splitpath(file_path), i.parts)
        end |>
        x -> sort(x, by=i->length(i.parts), rev=true) |>
        x -> length(x) == 0 ? nothing : first(x).uri

    return project
end

function find_testitems!(doc, server::LanguageServerInstance, jr_endpoint)
    if !ismissing(server.initialization_options) && get(server.initialization_options, "julialangTestItemIdentification", false)
        # Find which workspace folder the doc is in.
        parent_workspaceFolders = sort(filter(f -> startswith(doc._path, f), collect(server.workspaceFolders)), by=length, rev=true)

        # If the file is not in the workspace, we don't report nothing
        isempty(parent_workspaceFolders) && return

        project_uri = find_project_for_file(server.workspace,  get_uri(doc))
        package_uri = find_package_for_file(server.workspace,  get_uri(doc))

        if project_uri === nothing
            project_uri = filepath2uri(server.env_path)
        end

        if package_uri === nothing
            package_path = ""
            package_name = ""
        else
            package_path = uri2filepath(package_uri)
            package_name = server.workspace._packages[package_uri].name
        end

        project_path = ""
        if haskey(server.workspace._projects, project_uri)
            relevant_project = server.workspace._projects[project_uri]

            if haskey(relevant_project.deved_packages, package_uri)
                project_path = uri2filepath(project_uri)
            end
        end

        cst = getcst(doc)

        testitems = []

        for i in cst.args
            file_testitems = []
            file_errors = []

            TestItemDetection.find_test_items_detail!(i, file_testitems, file_errors)

            append!(testitems, [TestItemDetail(i.name, i.name, Range(doc, i.range), get_text(doc)[i.code_range], Range(doc, i.code_range), i.option_default_imports, string.(i.option_tags), nothing) for i in file_testitems])
            append!(testitems, [TestItemDetail("Test error", "Test error", Range(doc, i.range), nothing, nothing, nothing, nothing, i.error) for i in file_errors])
        end

        params = PublishTestItemsParams(
            get_uri(doc),
            get_version(doc),
            project_path,
            package_path,
            package_name,
            testitems
        )
        JSONRPC.send(jr_endpoint, textDocument_publishTestitems_notification_type, params)
    end
end
