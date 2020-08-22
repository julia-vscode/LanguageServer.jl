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
        error("The client and server have different textDocument versions for $(doc._uri).")
    end
    doc._version = params.textDocument.version

    if length(params.contentChanges) == 1 && !endswith(doc._uri, ".jmd") && !ismissing(first(params.contentChanges).range)
        tdcce = first(params.contentChanges)
        new_cst = _partial_update(doc, tdcce)
        scopepass(getroot(doc), doc)
        lint!(doc, server)
    else
        for tdcce in params.contentChanges
            applytextdocumentchanges(doc, tdcce)
        end
        parse_all(doc, server)
    end
end

function _partial_update(doc::Document, tdcce::TextDocumentContentChangeEvent)
    cst = getcst(doc)
    insert_range = get_offset(doc, tdcce.range)

    applytextdocumentchanges(doc, tdcce)

    updated_text = get_text(doc)

    i1, i2, loc1, loc2 = get_update_area(cst, insert_range)
    is = insert_size(tdcce.text, insert_range)
    if isempty(updated_text)
        empty!(cst.args)
        StaticLint.clear_meta(cst)
        cst.span = cst.fullspan = 0
    elseif 0 < i1 <= i2
        old_span = cst_len(cst, i1, i2)
        ps = ParseState(updated_text, loc1)
        args = EXPR[]
        if i1 == 1 && (ps.nt.kind == CSTParser.Tokens.WHITESPACE || ps.nt.kind == CSTParser.Tokens.COMMENT)
            CSTParser.next(ps)
            push!(args, CSTParser.mLITERAL(ps.nt.startbyte, ps.nt.startbyte, "", Tokens.NOTHING))
        else
            push!(args, CSTParser.parse(ps)[1])
        end
        prev_pos = -1
        while ps.nt.startbyte < old_span + loc1 + is && !(ps.done || kindof(ps.nt) === CSTParser.Tokens.ENDMARKER)
            if ps.nt.startbyte <= prev_pos
                throw(LSInfiniteLoop("Loop not progressing as it should."))
            else
                prev_pos = ps.nt.startbyte
            end
            push!(args, CSTParser.parse(ps)[1])
        end
        new_span = 0
        for i = 1:length(args)
            new_span += args[i].fullspan
        end
        # remove old blocks
        while old_span + is < new_span && i2 < length(cst.args)
            i2 += 1
            old_span += cst.args[i2].fullspan
        end
        for i = i1:i2
            StaticLint.clear_meta(cst.args[i])
        end
        deleteat!(cst.args, i1:i2)

        # insert new blocks
        for a in args
            insert!(cst.args, i1, a)
            CSTParser.setparent!(cst.args[i1], cst)
            i1 += 1
        end
    else
        StaticLint.clear_meta(cst)
        cst = CSTParser.parse(updated_text, true)
    end
    CSTParser.update_span!(cst)
    doc.cst = cst
    if typof(doc.cst) === CSTParser.FileH
        doc.cst.val = getpath(doc)
        set_doc(doc.cst, doc)
    end
end

insert_size(inserttext, insertrange) = sizeof(inserttext) - max(last(insertrange) - first(insertrange), 0) # OK, used to adjust EXPR spans

function cst_len(x, i1=1, i2=length(x.args))
    n = 0
    @inbounds for i = i1:i2
        n += x.args[i].fullspan
    end
    n
end

function get_update_area(cst, insert_range)
    loc1 = loc2 = 0
    i1 = i2 = 0

    while i1 < length(cst.args)
        i1 += 1
        a = cst.args[i1]
        if loc1 <= first(insert_range) <= loc1 + a.fullspan
            loc2 = loc1
            i2 = i1
            if !(loc1 <= last(insert_range) <= loc1 + a.fullspan)
                while i2 < length(cst.args)
                    i2 += 1
                    a = cst.args[i2]
                    if loc2 <= last(insert_range) <= loc2 + a.fullspan
                        if i2 < length(cst.args) && last(insert_range) <= loc2 + a.fullspan
                            i2 += 1
                        end
                        break
                    end
                    loc2 += a.fullspan
                end
            elseif i2 < length(cst.args) && last(insert_range) == loc1 + a.fullspan
                i2 += 1
            end
            break
        end
        loc1 += a.fullspan
    end
    return i1, i2, loc1, loc2
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
    if typof(doc.cst) === CSTParser.FileH
        doc.cst.val = getpath(doc)
        set_doc(doc.cst, doc)
    end

    scopepass(getroot(doc), doc)
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
                    DiagnosticSeverities
                    if typof(errs[i][2]) === CSTParser.ErrorToken
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
    top = EXPR(CSTParser.FileH, EXPR[])
    if isempty(blocks)
        return top, ps
    end

    for (startbyte, b) in blocks
        if typof(b) === CSTParser.LITERAL && kindof(b) == CSTParser.Tokens.TRIPLE_CMD && (startswith(b.val, "julia") || startswith(b.val, "{julia"))
            blockstr = b.val
            ps = CSTParser.ParseState(blockstr)
            # skip first line
            while ps.nt.startpos[1] == 1
                CSTParser.next(ps)
            end
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 3

            push!(top.args, CSTParser.mLITERAL(length(prec_str_size), length(prec_str_size), "", CSTParser.Tokens.STRING))

            args, ps = CSTParser.parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        elseif typof(b) === CSTParser.LITERAL && kindof(b) == CSTParser.Tokens.CMD && startswith(b.val, "j ")
            blockstr = b.val
            ps = CSTParser.ParseState(blockstr)
            CSTParser.next(ps)
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 1
            push!(top.args, CSTParser.mLITERAL(length(prec_str_size), length(prec_str_size), "", CSTParser.Tokens.STRING))

            args, ps = CSTParser.parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        end
    end

    prec_str_size = currentbyte:sizeof(str) # OK
    push!(top.args, CSTParser.mLITERAL(length(prec_str_size), length(prec_str_size), "", CSTParser.Tokens.STRING))

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
        CSTParser.parse(get_text(pdoc))
        if typof(pdoc.cst) === CSTParser.FileH
            pdoc.cst.val = getpath(pdoc)
            set_doc(pdoc.cst, pdoc)
        end
    else
        pdoc = getdocument(server, URI2(puri))
    end
    scopepass(getroot(pdoc), pdoc)
    # check whether child has been included automatically
    if any(getpath(d) == child_path for (k, d) in getdocuments_pair(server) if !(k in previous_server_docs))
        cdoc = getdocument(server, URI2(filepath2uri(child_path)))
        parse_all(cdoc, server)
        scopepass(getroot(cdoc))
        return true
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
