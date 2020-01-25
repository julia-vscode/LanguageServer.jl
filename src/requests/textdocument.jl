JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params) = DidOpenTextDocumentParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    server.isrunning = true
    uri = r.params.textDocument.uri
    if URI2(uri) in keys(server.documents)
        doc = server.documents[URI2(uri)]
        set_text!(doc, r.params.textDocument.text)
        doc._version = r.params.textDocument.version
        get_line_offsets(doc, true)
    else
        try_to_load_parents(uri2filepath(uri), server)

        if haskey(server.documents, URI2(uri))
            doc = server.documents[URI2(uri)]
        else
            doc = server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false, server)
            doc._version = r.params.textDocument.version
            if any(i->startswith(uri, filepath2uri(i)), server.workspaceFolders)
                doc._workspace_file = true
            end
            set_open_in_editor(doc, true)
            if is_ignored(uri, server)
                doc._runlinter = false
            end
        end
    end
    parse_all(doc, server)
end


JSONRPC.parse_params(::Type{Val{Symbol("julia/reloadText")}}, params) = DidOpenTextDocumentParams(params)
function process(r::JSONRPC.Request{Val{Symbol("julia/reloadText")},DidOpenTextDocumentParams}, server)
    server.isrunning = true
    uri = r.params.textDocument.uri
    if URI2(uri) in keys(server.documents)
        doc = server.documents[URI2(uri)]
        set_text!(doc, r.params.textDocument.text)
        doc._version = r.params.textDocument.version
    else
        doc = server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false, server)
        doc._version = r.params.textDocument.version
        if any(i->startswith(uri, filepath2uri(i)), server.workspaceFolders)
            doc._workspace_file = true
        end
        set_open_in_editor(doc, true)
        if is_ignored(uri, server)
            doc._runlinter = false
        end
    end
    get_line_offsets(doc)
    parse_all(doc, server)
end

JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params) = DidCloseTextDocumentParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    !haskey(server.documents, URI2(uri)) && return
    doc = server.documents[URI2(uri)]
    empty!(doc.diagnostics)
    publish_diagnostics(doc, server)
    if !is_workspace_file(doc)
        delete!(server.documents, URI2(uri))
    else
        set_open_in_editor(doc, false)
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params) = DidSaveTextDocumentParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")},DidSaveTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    doc = server.documents[URI2(uri)]
    parse_all(doc, server)
end


JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSave")}}, params) = WillSaveTextDocumentParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSave")},WillSaveTextDocumentParams}, server) end


JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSaveWaitUntil")}}, params) = WillSaveTextDocumentParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSaveWaitUntil")},WillSaveTextDocumentParams}, server)
    response = JSONRPC.Response(r.id, TextEdit[])
    send(response, server)
end


JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params) = DidChangeTextDocumentParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server::LanguageServerInstance)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        server.documents[URI2(r.params.textDocument.uri)] = Document(r.params.textDocument.uri, "", true, server)
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    if r.params.textDocument.version < doc._version
        # send(Dict("jsonrpc" => "2.0", "method" => "julia/getFullText", "params" => doc._uri), server)
        # return
        error("The client and server have different textDocument versions for $(doc._uri).")
    end
    doc._version = r.params.textDocument.version
    
    if length(r.params.contentChanges) == 1 && !endswith(doc._uri, ".jmd") && !ismissing(first(r.params.contentChanges).range)
        tdcce = first(r.params.contentChanges)
        skipscope = _partial_update(doc, tdcce) 
        @info [round((c/sum(update_count))*100, sigdigits = 4) for c in update_count]
        if !skipscope # we've updated a teriminal expr where there's no need to run scoping.
            scopepass(getroot(doc), doc)
            StaticLint.check_all(getcst(doc), server.lint_options, server)
        end
        empty!(doc.diagnostics)
        mark_errors(doc, doc.diagnostics)
        publish_diagnostics(doc, server)
    else
        for tdcce in r.params.contentChanges
            applytextdocumentchanges(doc, tdcce)
        end
        parse_all(doc, server)
    end
end

function update_parent_spans!(x::EXPR)
    CSTParser.update_span!(x)
    if CSTParser.parentof(x) isa EXPR
        update_parent_spans!(CSTParser.parentof(x))
    end
end

const update_count = [0, 0]

# checks whether we can update a terminal token with no need to run a scopepass
# Handled states:
# 1: Digit added to existing INTEGER or FLOAT
# 2: ws added to existing ws
# 3: edits of IDENT (where not a Bindings name, part of a DOT expr or macrocall)
function _noimpact_partial_update(cst, insert_range, insert_text, old_text)
    if first(insert_range) == last(insert_range)
        # in the following we can treat an arbitrary string of spaces as a single space
        # pos is the insert offset from start of expr
        x, pos = get_insert_expr(cst, first(insert_range), first(insert_text))
        (!(x isa EXPR) || x.args !== nothing) && return false

        if length(insert_text) == 1 && _valid_number_addition(x, pos, insert_text)
            x.val = edit_string(x.val, pos, insert_text)
            x.span += 1
            x.fullspan += 1
            update_parent_spans!(x)
            update_count[1] += 1
            return true
        elseif _valid_ws_add(x, pos, insert_range, insert_text, old_text)
            x.fullspan += length(insert_text)
            update_parent_spans!(x)
            update_count[1] += 1
            return true
        elseif length(insert_text) == 1 && typof(x) === CSTParser.IDENTIFIER && _valid_id_edit(x, pos, insert_text)
            newval = edit_string(x.val, pos, insert_text)
            if (!StaticLint.hasref(x) || refof(x) isa SymbolServer.SymStore) || 
                (!StaticLint.hasbinding(x) && !_id_is_name(x) &&
                !(parentof(x) isa EXPR && typof(parentof(x)) === CSTParser.BinaryOpCall && kindof(parentof(x).args[2]) === CSTParser.Tokens.DOT) &&
                !(parentof(x) isa EXPR && typof(parentof(x)) === CSTParser.MacroName))
                x.val = newval
                x.span += 1
                x.fullspan += 1
                update_parent_spans!(x)
                update_count[1] += 1
                StaticLint.clear_ref(x)
                StaticLint.resolve_ref(x, StaticLint.retrieve_scope(x), StaticLint.State(nothing, nothing, String[], scopeof(cst), false, EXPR[], cst.meta.error.server))
                return true
            end
        end
    elseif isempty(insert_text)
        x, pos = get_deletion_expr(cst, insert_range)
        (pos == 1:0 || x.args !== nothing) && return false
        if _valid_ws_delete(x, pos, insert_range, old_text)
            x.fullspan -= (length(insert_range) - 1)
            update_parent_spans!(x)
            update_count[1] += 1
            return true
        elseif _valid_int_delete(x, pos)
            newval = string(x.val[1:first(pos)], x.val[nextind(x.val, last(pos)):end])
            x.val = newval
            x.span -= length(pos) - 1
            x.fullspan -= length(pos) - 1
            update_parent_spans!(x)
            update_count[1] += 1
            return true
        elseif typof(x) == CSTParser.IDENTIFIER && last(pos) <= x.span && length(pos) < x.span &&
                ((!StaticLint.hasref(x) || refof(x) isa SymbolServer.SymStore) || 
                (!StaticLint.hasbinding(x) && !_id_is_name(x) &&
                !(parentof(x) isa EXPR && StaticLint._binary_assert(parentof(x), CSTParser.Tokens.DOT)) &&
                !(parentof(x) isa EXPR && typof(parentof(x)) === CSTParser.MacroName)))
            newval = string(x.val[1:first(pos)], x.val[nextind(x.val, last(pos)):end])
            CSTParser.Tokenize.Lexers.next_token(CSTParser.Tokenize.tokenize(newval)).kind !== Tokens.IDENTIFIER && return false
            x.val = newval
            x.span -= length(pos) - 1
            x.fullspan -= length(pos) - 1
            update_parent_spans!(x)
            update_count[1] += 1
            StaticLint.clear_ref(x)
            StaticLint.resolve_ref(x, StaticLint.retrieve_scope(x), StaticLint.State(nothing, nothing, String[], scopeof(cst), false, EXPR[], cst.meta.error.server))
            return true
        end
    end
    return false
end

# Checks whether ws can be deleted:
# 1. only remove spaces and there remains ws
# 2. if we're deleting a newline, make sure there's still one in the remaining ws text
function _valid_ws_delete(x, pos, insert_range, old_text)
    preceding_ws = SubString(old_text, nextind(old_text, first(insert_range) - first(pos) + x.span):first(insert_range))
    trailing_ws = SubString(old_text, nextind(old_text, last(insert_range)):first(insert_range) - first(pos) + x.fullspan)
    return (x.span < first(pos) || first(pos) == x.span && last(pos) < x.fullspan) && 
    (
        all(c->c === ' ', SubString(old_text, nextind(old_text, first(insert_range)):last(insert_range))) ||
        (any(c->c === '\n', preceding_ws) || any(c->c === '\n', trailing_ws))
    )
end

function _valid_ws_add(x, pos, insert_range, insert_text, old_text)
    preceding_ws = SubString(old_text, nextind(old_text, first(insert_range) - first(pos) + x.span):first(insert_range))
    trailing_ws = SubString(old_text, nextind(old_text, last(insert_range)):first(insert_range) - first(pos) + x.fullspan)
    # needs change to allow arbitrary length additions (where no newline is added without there already being one)
    return (pos > x.span || (x.span < x.fullspan && pos == x.span)) && 
            (all(c -> c === ' ', insert_text) ||
            (all(c -> c === ' ' || c === '\n', insert_text) && (any(c -> c === '\n', preceding_ws) ||
            any(c -> c === '\n', trailing_ws))))
end

function _valid_number_addition(x, pos, insert_text)
    (CSTParser.is_integer(x) || CSTParser.is_float(x)) && isdigit(first(insert_text)) && parentof(x) isa EXPR && pos <= x.span
end

function _valid_int_delete(x, pos)
    CSTParser.is_integer(x) && last(pos) <= x.span && length(pos) < x.span
end

function _valid_id_edit(x, pos, insert_text)
    ((pos == 0 && CSTParser.Tokenize.Lexers.is_identifier_start_char(first(insert_text))) ||
    (0 < pos <= x.span && CSTParser.Tokenize.Lexers.is_identifier_char(first(insert_text)))) &&
    (newval = string(x.val[1:pos], insert_text, x.val[pos+1:end]);CSTParser.Tokenize.Lexers.next_token(CSTParser.Tokenize.tokenize(newval)).kind === Tokens.IDENTIFIER)
end

function _id_is_name(x)
    # assumes hasref(x)
    x.meta.ref isa StaticLint.Binding && x.meta.ref.name === x
end

function _partial_update(doc::Document, tdcce::TextDocumentContentChangeEvent)
    cst = getcst(doc)
    insert_range = get_offset(doc, tdcce.range)
    noimpact = _noimpact_partial_update(cst, insert_range, tdcce.text, get_text(doc))
    updated_text = edit_string(get_text(doc), insert_range, tdcce.text)
    set_text!(doc, updated_text)
    doc._line_offsets = nothing

    noimpact && return true

    update_count[2] += 1
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
        while ps.nt.startbyte < old_span + loc1 + is && !ps.done
            push!(args, CSTParser.parse(ps)[1])
        end
        new_span = 0
        for i = 1:length(args)
            new_span += args[i].fullspan
        end
        # remove old blocks
        while old_span + is < new_span && i2 < length(cst.args)
            i2+=1 
            old_span += cst.args[i2].fullspan
        end
        for i = i1:i2
            StaticLint.clear_meta(cst.args[i])
        end
        deleteat!(cst.args, i1:i2)

        #insert new blocks
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
        doc.cst.val = doc.path
        set_doc(doc.cst, doc)
    end
    return false
end

insert_size(inserttext, insertrange) = sizeof(inserttext) - max(last(insertrange) - first(insertrange), 0)

function cst_len(x, i1 = 1, i2 = length(x.args))
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
                            i2+=1
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


function applytextdocumentchanges(doc::Document, tdcce::TextDocumentContentChangeEvent)
    if ismissing(tdcce.range) && ismissing(tdcce.rangeLength)
        # No range given, replace all text
        set_text!(doc, tdcce.text)
    else
        editrange = get_offset(doc, tdcce.range)
        set_text!(doc, edit_string(get_text(doc), editrange, tdcce.text))
    end
    doc._line_offsets = nothing
end

function edit_string(text, editrange, edit)
    if first(editrange) == last(editrange) == 0
        string(edit, text)
    elseif first(editrange) == 0 && last(editrange) == sizeof(text)
        edit
    elseif first(editrange) == 0
        string(edit, text[nextind(text, last(editrange)):end])
    elseif first(editrange) == last(editrange) == sizeof(text)
        string(text, edit)
    elseif last(editrange) == sizeof(text)
        string(text[1:first(editrange)], edit)
    else
        string(text[1:first(editrange)], edit, text[min(lastindex(text), nextind(text, last(editrange))):end])
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
        doc.cst.val = doc.path
        set_doc(doc.cst, doc)
    end
    
    scopepass(getroot(doc), doc)
    StaticLint.check_all(getcst(doc), server.lint_options, server)
    empty!(doc.diagnostics)
    mark_errors(doc, doc.diagnostics)
    
    publish_diagnostics(doc, server)
end

function mark_errors(doc, out = Diagnostic[])
    line_offsets = get_line_offsets(doc)
    errs = StaticLint.collect_hints(getcst(doc))
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
                    if typof(errs[i][2]) === CSTParser.ErrorToken
                        push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), 1, "Julia", "Julia", "Parsing error", missing))
                    elseif typof(errs[i][2]) === CSTParser.IDENTIFIER && !StaticLint.haserror(errs[i][2])
                        push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), 2, "Julia", "Julia", "Missing reference: $(errs[i][2].val)", missing))
                    elseif StaticLint.haserror(errs[i][2]) && StaticLint.errorof(errs[i][2]) isa StaticLint.LintCodes
                        push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), 3, "Julia", "Julia", get(StaticLint.LintCodeDescriptions, StaticLint.errorof(errs[i][2]), ""), missing))
                    end
                    i += 1
                    i>n && break
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

function publish_diagnostics(doc::Document, server)
    if server.runlinter
        publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, doc.diagnostics)
        response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, publishDiagnosticsParams)
    else
        response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(doc._uri, Diagnostic[]))
    end
    send(response, server)
end


function clear_diagnostics(uri::URI2, server)
    doc = server.documents[uri]
    empty!(doc.diagnostics)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(doc._uri, Diagnostic[]))
    send(response, server)
end 

function clear_diagnostics(server)
    for (uri, doc) in server.documents
        clear_diagnostics(uri, server)
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
    top = EXPR(CSTParser.Block, EXPR[])
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

            push!(top.args, CSTParser.mLITERAL(sizeof(str[prec_str_size]), sizeof(str[prec_str_size]) , "", CSTParser.Tokens.STRING))

            args, ps = CSTParser.parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        elseif typof(b) === CSTParser.LITERAL && kindof(b) == CSTParser.Tokens.CMD && startswith(b.val, "j ")
            blockstr = b.val
            ps = CSTParser.ParseState(blockstr)
            CSTParser.next(ps)
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 1
            push!(top.args, CSTParser.mLITERAL(sizeof(str[prec_str_size]), sizeof(str[prec_str_size]), "", CSTParser.Tokens.STRING))

            args, ps = parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        end
    end
    prec_str_size = currentbyte:sizeof(str)
    push!(top.args, CSTParser.mLITERAL(sizeof(str[prec_str_size]), sizeof(str[prec_str_size]), "", CSTParser.Tokens.STRING))

    return top, ps
end

function search_for_parent(dir::String, file::String, drop = 3, parents = String[])
    drop<1 && return parents
    !isdir(dir) && return parents
    for f in readdir(dir)
        if endswith(f, ".jl")
            # Could be sped up?
            s = read(joinpath(dir, f), String)
            occursin(file, s) && push!(parents, joinpath(dir, f))
        end
    end
    search_for_parent(splitdir(dir)[1], file, drop - 1, parents)
    return parents
end


function is_parentof(parent_path, child_path, server)
    !(hasreadperm(parent_path) && isvalidjlfile(parent_path)) && return false
    previous_server_docs = collect(keys(server.documents)) # additions to this to be removed at end
    # load parent file
    puri = filepath2uri(parent_path)
    pdoc = server.documents[URI2(puri)] = Document(puri, read(parent_path, String), false, server)
    parse_all
    CSTParser.parse(get_text(pdoc))
    if typof(pdoc.cst) === CSTParser.FileH
        pdoc.cst.val = pdoc.path
        set_doc(pdoc.cst, pdoc)
    end
    scopepass(getroot(pdoc), pdoc)
    # check whether child has been included automatically
    if any(uri2filepath(k._uri) == child_path for k in keys(server.documents) if !(k in previous_server_docs))
        cdoc = server.documents[URI2(filepath2uri(child_path))]
        parse_all(cdoc, server)
        scopepass(getroot(cdoc))
        return true
    else
        # clean up
        foreach(k-> !(k in previous_server_docs) && delete!(server.documents, k), keys(server.documents))
        return false
    end
end

function try_to_load_parents(child_path, server)
    for p in search_for_parent(splitdir(child_path)...)
        success = is_parentof(p, child_path, server)
        if success 
            return try_to_load_parents(p, server)
        end
    end
end

#utils
# whether to choose the lhs or rhs expr given insert `ch`
function lhs_expr_boundary(lhs, rhs, ch::Char)
    if isdigit(ch)
        if typof(rhs) === CSTParser.LITERAL && (kindof(rhs) === CSTParser.Tokens.INTEGER || kindof(rhs) === CSTParser.Tokens.FLOAT)
            return false
        elseif typof(lhs) === CSTParser.LITERAL && (kindof(lhs) === CSTParser.Tokens.INTEGER || kindof(lhs) === CSTParser.Tokens.FLOAT) && lhs.span == lhs.fullspan
            return true
        else
            # handle other numeric literals
            # handle appending digit onto end of identifier lhs.span == lhs.fullspan
        end
    elseif ch === ' ' && lhs.span < lhs.fullspan
        return true
    end
    # default to choosing rhs?
    return false
end

# gets ultimate child node at offset, makes lhs/rhs decision when offset is
# between exprs according to which expr will be modified by `ch`.
# i.e.
#  expr:     asdfsd + 123123
#  edit:             ^^
# 
# e.g. will choose the lhs (`+ `) when ch is a space ` `but will choose the rhs
# when ch is a digit
function get_insert_expr(x, offset, ch, pos = 0)
    if x.args === nothing
        if offset == pos 
            return x, 0
        elseif pos < offset < pos + x.span 
            return x, offset - pos
        elseif offset == pos + x.span
            return x, x.span
        elseif pos + x.span < offset < pos + x.fullspan
            return x, offset - pos
        elseif offset == pos + x.fullspan
            return x, x.fullspan
        else
            @warn "this had better be unreachable"
            return x, offset - pos
        end
    elseif isempty(x.args)
        return x, offset - pos
    else
        for i = 1:length(x.args)
            arg = x.args[i]
            if pos < offset < (pos + arg.span) # within expr body
                return get_insert_expr(arg, offset, ch, pos)
            elseif offset == pos # start of expr
                if i == 1
                    return get_insert_expr(arg, offset, ch, pos)
                elseif lhs_expr_boundary(x.args[i-1], x.args[i], ch)
                    return get_insert_expr(x.args[i-1], offset, ch, pos - x.args[i-1].fullspan)
                else
                    return get_insert_expr(x.args[i], offset, ch, pos)
                end
            elseif offset == pos + arg.span
                if arg.span == arg.fullspan
                    if i == length(x.args)
                        return get_insert_expr(x.args[i], offset, ch, pos)
                    else
                        # continue to next expr
                        # return get_expr2(x.args[i + 1], offset, text, pos + arg.fullspan)
                    end
                else
                    return get_insert_expr(x.args[i], offset, ch, pos)
                end
            elseif offset == pos + arg.fullspan
                if i == length(x.args)
                    return get_insert_expr(x.args[i], offset, ch, pos)
                else
                    # continue to next expr
                    # return get_expr2(x.args[i + 1], offset, text, pos + arg.fullspan)
                end
            elseif pos + arg.span < offset < pos + arg.fullspan
                return get_insert_expr(x.args[i], offset, ch, pos)
            end
            pos += arg.fullspan
        end
        return nothing, pos
    end
end

function get_deletion_expr(x::EXPR, offset_range::UnitRange{Int}, pos::Int = 0)
    if x.args === nothing && pos <= first(offset_range) && last(offset_range) <= (pos + x.fullspan) # within expr body
        return x, offset_range .- pos
    elseif x.args === nothing || isempty(x.args)
        return x, 1:0
    else
        for i in 1:length(x.args)
            arg = x.args[i]
            if pos <= first(offset_range) && last(offset_range) <= (pos + arg.fullspan) # within expr body
                return get_deletion_expr(arg, offset_range, pos)
            end
            pos += arg.fullspan
        end
    end
    return x, 1:0
end
