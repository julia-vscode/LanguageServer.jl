function textDocument_didOpen_notification(params::DidOpenTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    if hasdocument(server, uri)
        doc = getdocument(server, uri)
        set_text_document!(doc, TextDocument(uri, params.textDocument.text, params.textDocument.version))
        set_open_in_editor(doc, true)
    else
        doc = Document(TextDocument(uri, params.textDocument.text, params.textDocument.version), false, server)
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

    if endswith(get_uri(doc).path, ".jmd")
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
    ps = CSTParser.ParseState(get_text(doc))
    StaticLint.clear_meta(getcst(doc))
    if endswith(get_uri(get_text_document(doc)).path, ".jmd")
        doc.cst, ps = parse_jmd(ps, get_text(doc))
    else
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
                        code_details = if code === StaticLint.LoopOverLength
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

function parse_jmd(ps, str)
    currentbyte = 1
    blocks = []
    while ps.nt.kind != Tokens.ENDMARKER
        CSTParser.next(ps)
        if ps.t.kind == Tokens.CMD || ps.t.kind == Tokens.TRIPLE_CMD
            push!(blocks, (ps.t.startbyte, CSTParser.INSTANCE(ps)))
        end
    end
    top = EXPR(:file, EXPR[], nothing)
    if isempty(blocks)
        return top, ps
    end

    for (startbyte, b) in blocks
        if CSTParser.ismacrocall(b) && headof(b.args[1]) === :globalrefcmd && headof(b.args[3]) === :TRIPLESTRING && (startswith(b.args[3].val, "julia") || startswith(b.args[3].val, "{julia"))

            blockstr = b.args[3].val
            ps = CSTParser.ParseState(blockstr)
            # skip first line
            while ps.nt.startpos[1] == 1
                CSTParser.next(ps)
            end
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 3

            push!(top, EXPR(:STRING, length(prec_str_size), length(prec_str_size)))

            args, ps = CSTParser.parse(ps, true)
            for a in args.args
                push!(top, a)
            end

            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        elseif CSTParser.ismacrocall(b) && headof(b.args[1]) === :globalrefcmd && headof(b.args[3]) === :STRING && b.val !== nothing && startswith(b.val, "j ")
            blockstr = b.args[3].val
            ps = CSTParser.ParseState(blockstr)
            CSTParser.next(ps)
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 1
            push!(top, EXPR(:STRING, length(prec_str_size), length(prec_str_size)))

            args, ps = CSTParser.parse(ps, true)
            for a in args.args
                push!(top, a)
            end

            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        end
    end

    prec_str_size = currentbyte:sizeof(str) # OK
    push!(top, EXPR(:STRING, length(prec_str_size), length(prec_str_size)))
    CSTParser.update_span!(top)

    return top, ps
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
                    isvalid(s) || continue
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
            isvalid(s) || return false
            s
        catch err
            isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
            return false
        end
        pdoc = Document(puri, content, false, server)
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
