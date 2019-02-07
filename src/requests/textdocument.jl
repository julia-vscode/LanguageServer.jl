function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    server.isrunning = true
    uri = r.params.textDocument.uri
    if URI2(uri) in keys(server.documents)
        doc = server.documents[URI2(uri)]
        doc._content = r.params.textDocument.text
    else
        server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false, server)
        doc = server.documents[URI2(uri)]
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
        error("TextDocumentContentChangeEvent is older than existing Document version.")
    end
    doc._version = r.params.textDocument.version
    
    # if length(r.params.contentChanges) == 1
    #     partial_success = _partial_parse(doc, r.params.contentChanges[1])
    # end

    for tdcce in r.params.contentChanges
        applytextdocumentchanges(doc, tdcce)
    end
    doc._line_offsets = nothing
    parse_all(doc, server)
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
        text = string(text[1:first(editrange)], edit, text[nextind(text, last(editrange)):end])
    end    
end

function _partial_parse(doc, tdcce)
    tdcce.range == tdcce.rangeLength == nothing && return false
    editrange = get_offset(doc, tdcce.range)
    stack = _get_range_stack(doc.code.cst, editrange)
    
    if last(stack)[1] isa CSTParser.IDENTIFIER
        !all(CSTParser.Tokenize.Lexers.is_identifier_char, tdcce.text) && return false
        first(editrange) == last(stack)[2] && (isempty(tdcce.text) || !CSTParser.Tokenize.Lexers.is_identifier_start_char(first(tdcce.text))) && return false
        last(stack)[2] + last(stack)[1].span < last(editrange) && return false
        oldtok = deepcopy(last(stack)[1])
        newtext = edit_string(oldtok.val, broadcast(-, editrange, last(stack)[2]), tdcce.text)
        dl = sizeof(oldtok.val) - sizeof(last(stack)[1].val)
        
        _edit_expr_args(stack[end-1][1], CSTParser.IDENTIFIER(oldtok.fullspan + dl, oldtok.span + dl, newtext), last(stack)[3])
        for i = 1:length(stack) - 1
            stack[i][1].fullspan += dl
            stack[i][1].span += dl
        end
        return true
    end

    return false 
end

function _get_range_stack(x, offset::T, pos = 0, child_pos = nothing, stack = []) where T <: Union{Int,UnitRange{Int}}
    push!(stack, (x, pos, child_pos))
    for (i, a) in enumerate(x)
        if pos <= first(offset) <= pos + a.fullspan && pos <= last(offset) <= pos + a.fullspan
            return _get_range_stack(a, offset, pos, i, stack)
        else
            pos += a.fullspan
        end
    end
    return stack
end

function _edit_expr_args(x::EXPR, t, i)
    x.args[i] = t
end

function _edit_expr_args(x::T, t, i) where T <: Union{BinaryOpCall,BinarySyntaxOpCall}
    if i == 1
        x.arg1 = t
    elseif i == 2
        x.op = t
    elseif i == 3
        x.arg2 = t
    else
        error("Attempt to access out of bounds.")
    end
end

function _edit_expr_args(x::UnaryOpCall, t, i) 
    if i == 1
        x.op = t
    elseif i == 2
        x.arg1 = t
    else
        error("Attempt to access out of bounds.")
    end
end

function _edit_expr_args(x::UnarySyntaxOpCall, t, i) 
    if i == 1
        x.arg1 = t
    elseif i == 2
        x.arg2 = t
    else
        error("Attempt to access out of bounds.")
    end
end

function _edit_expr_args(x::WhereOpCall, t, i) 
    if i == 1
        x.arg1 = t
    elseif i == 2
        x.op = t
    elseif 2 < i <= length(x.args) + 2
        x.args[i-2] = t
    else
        error("Attempt to access out of bounds.")
    end
end

function _edit_expr_args(x::CSTParser.ChainOpCall, t, i) 
    if i == 1
        x.cond = t
    elseif i == 2
        x.op1 = t
    elseif i == 3
        x.arg1 = t
    elseif i == 4
        x.op2 = t
    elseif i == 5
        x.arg2 = t
    else
        error("Attempt to access out of bounds.")
    end
end