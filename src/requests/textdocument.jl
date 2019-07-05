function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    server.isrunning = true
    uri = r.params.textDocument.uri
    if URI2(uri) in keys(server.documents)
        doc = server.documents[URI2(uri)]
        doc._content = r.params.textDocument.text
        doc._version = r.params.textDocument.version
    else
        server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false, server)
        doc = server.documents[URI2(uri)]
        doc._version = r.params.textDocument.version
        if any(i->startswith(uri, filepath2uri(i)), server.workspaceFolders)
            doc._workspace_file = true
        end
        set_open_in_editor(doc, true)
        if is_ignored(uri, server)
            doc._runlinter = false
        end
    end
    parse_all(doc, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/reloadText")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("julia/reloadText")},DidOpenTextDocumentParams}, server)
    server.isrunning = true
    uri = r.params.textDocument.uri
    if URI2(uri) in keys(server.documents)
        doc = server.documents[URI2(uri)]
        doc._content = r.params.textDocument.text
        doc._version = r.params.textDocument.version
    else
        doc = server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false, server)
        doc = server.documents[URI2(uri)]
        doc._version = r.params.textDocument.version
        if any(i->startswith(uri, filepath2uri(i)), server.workspaceFolders)
            doc._workspace_file = true
        end
        set_open_in_editor(doc, true)
        if is_ignored(uri, server)
            doc._runlinter = false
        end
    end
    parse_all(doc, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

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


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params)
    return DidSaveTextDocumentParams(params)
end
 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")},DidSaveTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    doc = server.documents[URI2(uri)]
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSave")}}, params)
    return WillSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSave")},WillSaveTextDocumentParams}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSaveWaitUntil")}}, params)
    return WillSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSaveWaitUntil")},WillSaveTextDocumentParams}, server)
    response = JSONRPC.Response(r.id, TextEdit[])
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        server.documents[URI2(r.params.textDocument.uri)] = Document(r.params.textDocument.uri, "", true, server)
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    if r.params.textDocument.version < doc._version
        write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "method" => "julia/getFullText", "params" => doc._uri)), server.debug_mode)
        return
    end
    doc._version = r.params.textDocument.version
    
    if length(r.params.contentChanges) == 1 && !endswith(doc._uri, ".jmd") && first(r.params.contentChanges).range !== nothing
        tdcce = first(r.params.contentChanges)
        new_cst = _partial_update(doc, tdcce) 
        ls_diags = Diagnostic[]
        if server.runlinter && doc._runlinter
            scopepass(getroot(doc))
            mark_errors(doc, ls_diags)
        end
        send(JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(doc._uri, ls_diags)), server)
    else
        for tdcce in r.params.contentChanges
            applytextdocumentchanges(doc, tdcce)
        end
        doc._line_offsets = nothing
        parse_all(doc, server)
    end    
end

function _partial_update(doc::Document, tdcce::TextDocumentContentChangeEvent)
    cst = getcst(doc)
    # cst = CSTParser.parse(doc._content, true)
    insert_range = get_offset(doc, tdcce.range)
    doc._content = updated_text = edit_string(doc._content, insert_range, tdcce.text)
    doc._line_offsets = nothing

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
    if doc.cst.typ === CSTParser.FileH
        doc.cst.val = doc.path
        doc.cst.ref = doc
    end
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
    if tdcce.range == tdcce.rangeLength == nothing
        # No range given, replace all text
        doc._content = tdcce.text
    else
        editrange = get_offset(doc, tdcce.range)
        doc._content = edit_string(doc._content, editrange, tdcce.text)
    end
end

function edit_string(text, editrange, edit)
    if first(editrange) == last(editrange) == 0
        text = string(edit, text)
    elseif first(editrange) == 0 && last(editrange) == sizeof(text)
        text = edit
    elseif first(editrange) == 0
        text = string(edit, text[nextind(text, last(editrange)):end])
    elseif first(editrange) == last(editrange) == sizeof(text)
        text = string(text, edit)
    elseif last(editrange) == sizeof(text)
        text = string(text[1:first(editrange)], edit)
    else
        text = string(text[1:first(editrange)], edit, text[min(lastindex(text), nextind(text, last(editrange))):end])
    end    
end

function check_refs(doc::Document)
    binds, refs = [], []
    for doc1 in doc.server.documents
        if doc1[2].root == doc.root
            StaticLint.collect_bindings_refs(doc1[2].cst, binds, refs)
        end
    end
    urefs = []
    for r in refs
        # if (r.ref isa CSTParser.Binding && r.ref.val isa CSTParser.EXPR) && !(r.ref in binds || r.ref.val in binds)
        if !(any(r.ref == b.binding for b in binds) || r.ref isa SymbolServer.SymStore || r.ref isa String)
            push!(urefs, r)
        end
    end
    binds, refs, urefs
end
