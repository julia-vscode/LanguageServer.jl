function textDocument_didOpen_notification(params::DidOpenTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    if hasdocument(server, URI2(uri))
        doc = getdocument(server, URI2(uri))
        set_text!(doc, params.textDocument.text)
        doc._version = params.textDocument.version
        set_open_in_editor(doc, true)
        get_line_offsets(doc, true)
    else
        doc = Document(uri, params.textDocument.text, false, server)
        setdocument!(server, URI2(uri), doc)
        doc._version = params.textDocument.version
        doc._workspace_file = any(i -> startswith(uri, filepath2uri(i)), server.workspaceFolders)
        set_open_in_editor(doc, true)

        fpath = getpath(doc)

        !isempty(fpath) && try_to_load_parents(fpath, server)
    end
    parse_all(doc, server)
end


function textDocument_didClose_notification(params::DidCloseTextDocumentParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    doc = getdocument(server, URI2(uri))

    if is_workspace_file(doc)
        set_open_in_editor(doc, false)
    else
        if any(d.root == doc.root && (d._open_in_editor || is_workspace_file(d)) for (uri, d::Document) in getdocuments_pair(server) if d != doc)
            # If any other open document shares doc's root we just mark it as closed...
            set_open_in_editor(doc, false)
        else
            # ...otherwise we delete all documents that share root with doc.
            for (u, d) in getdocuments_pair(server)
                if d.root == doc.root
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
    doc = getdocument(server, URI2(uri))
    if params.text isa String
        if get_text(doc) != params.text
            JSONRPC.send(conn, window_showMessage_notification_type, ShowMessageParams(MessageTypes.Error, "Julia Extension: Please contact us! Your extension just crashed with a bug that we have been trying to replicate for a long time. You could help the development team a lot by contacting us at https://github.com/julia-vscode/julia-vscode so that we can work together to fix this issue."))
            throw(LSSyncMismatch("Mismatch between server and client text for $(doc._uri). _open_in_editor is $(doc._open_in_editor). _workspace_file is $(doc._workspace_file). _version is $(doc._version)."))
        end
    end
    parse_all(doc, server)
end


function textDocument_willSave_notification(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
end


function textDocument_willSaveWaitUntil_request(params::WillSaveTextDocumentParams, server::LanguageServerInstance, conn)
    return TextEdit[]
end


function textDocument_didChange_notification(params::DidChangeTextDocumentParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, URI2(params.textDocument.uri))
    if params.textDocument.version < doc._version
        error("The client and server have different textDocument versions for $(doc._uri). LS version is $(doc._version), request version is $(params.textDocument.version).")
    end
    doc._version = params.textDocument.version

    for tdcce in params.contentChanges
        applytextdocumentchanges(doc, tdcce)
    end
    parse_all(doc, server)
end

function convert_lsrange_to_jlrange(doc::Document, range::Range)
    start_offset_ls = get_offset2(doc, range.start.line, range.start.character)
    stop_offset = get_offset2(doc, range.stop.line, range.stop.character)

    text = get_text(doc)

    # we use prevind for the stop value here because Julia stop values in
    # a range are inclusive, while the stop value is exclusive in a LS
    # range
    return start_offset_ls:prevind(text, stop_offset)
end

function applytextdocumentchanges(doc::Document, tdcce::TextDocumentContentChangeEvent)
    if ismissing(tdcce.range) && ismissing(tdcce.rangeLength)
        # No range given, replace all text
        set_text!(doc, tdcce.text)
    else
        editrange = convert_lsrange_to_jlrange(doc, tdcce.range)
        text = get_text(doc)
        new_text = string(text[1:prevind(text, editrange.start)], tdcce.text, text[nextind(text, editrange.stop):lastindex(text)])
        set_text!(doc, new_text)
    end
end

function parse_all(doc::Document, server::LanguageServerInstance)
    ps = CSTParser.ParseState(get_text(doc))
    StaticLint.clear_meta(getcst(doc))
    if endswith(doc._uri, ".jmd")
        doc.cst, ps = parse_jmd(ps, get_text(doc))
    else
        doc.cst, ps = CSTParser.parse(ps, true)
    end
    if headof(doc.cst) === :file
        doc.cst.val = getpath(doc)
        set_doc(doc.cst, doc)
    end
    semantic_pass(getroot(doc), doc)

    lint!(doc, server)
end

function mark_errors(doc, out=Diagnostic[])
    line_offsets = get_line_offsets(doc)
    errs = StaticLint.collect_hints(getcst(doc), doc.server, doc.server.lint_missingrefs)
    n = length(errs)
    n == 0 && return out
    i = 1
    start = true
    offset = errs[i][1]
    r = Int[0, 0]
    pos = 0
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
                    if headof(errs[i][2]) === :errortoken
                        push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), DiagnosticSeverities.Error, "Julia", "Julia", "Parsing error", missing, missing))
                    elseif CSTParser.isidentifier(errs[i][2]) && !StaticLint.haserror(errs[i][2])
                        push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), DiagnosticSeverities.Warning, "Julia", "Julia", "Missing reference: $(errs[i][2].val)", missing, missing))
                    elseif StaticLint.haserror(errs[i][2]) && StaticLint.errorof(errs[i][2]) isa StaticLint.LintCodes
                        if StaticLint.errorof(errs[i][2]) === StaticLint.UnusedFunctionArgument
                            push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), DiagnosticSeverities.Hint, "Julia", "Julia", get(StaticLint.LintCodeDescriptions, StaticLint.errorof(errs[i][2]), ""), [DiagnosticTags.Unnecessary], missing))
                        else
                            push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), DiagnosticSeverities.Information, "Julia", "Julia", get(StaticLint.LintCodeDescriptions, StaticLint.errorof(errs[i][2]), ""), missing, missing))
                        end
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

isunsavedfile(doc::Document) = startswith(doc._uri, "untitled:") # Not clear if this is consistent across editors.

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
    params = PublishDiagnosticsParams(doc._uri, doc._version, diagnostics)
    JSONRPC.send(conn, textDocument_publishDiagnostics_notification_type, params)
end

function clear_diagnostics(uri::URI2, server, conn)
    doc = getdocument(server, uri)
    empty!(doc.diagnostics)
    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, doc._version, Diagnostic[])
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

            push!(top.args, EXPR(:STRING, length(prec_str_size), length(prec_str_size)))

            args, ps = CSTParser.parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        elseif CSTParser.ismacrocall(b) && headof(b.args[1]) === :globalrefcmd && headof(b.args[3]) === :STRING && b.val !== nothing && startswith(b.val, "j ")
            blockstr = b.args[3].val
            ps = CSTParser.ParseState(blockstr)
            CSTParser.next(ps)
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 1
            push!(top.args, EXPR(:STRING, length(prec_str_size), length(prec_str_size)))

            args, ps = CSTParser.parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        end
    end

    prec_str_size = currentbyte:sizeof(str) # OK
    push!(top.args, EXPR(:STRING, length(prec_str_size), length(prec_str_size)))

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
    if !hasdocument(server, URI2(puri))
        content = try
            s = read(parent_path, String)
            isvalid(s) || return false
            s
        catch err
            isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
            return false
        end
        pdoc = Document(puri, content, false, server)
        setdocument!(server, URI2(puri), pdoc)
        CSTParser.parse(get_text(pdoc), true)
        if headof(pdoc.cst) === :file
            pdoc.cst.val = getpath(pdoc)
            set_doc(pdoc.cst, pdoc)
        end
    else
        pdoc = getdocument(server, URI2(puri))
    end
    semantic_pass(getroot(pdoc), pdoc)
    # check whether child has been included automatically
    if any(getpath(d) == child_path for (k, d) in getdocuments_pair(server) if !(k in previous_server_docs))
        cdoc = getdocument(server, URI2(filepath2uri(child_path)))
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
