const serverCapabilities = ServerCapabilities(
                        TextDocumentSyncKind["Full"],
                        true, #hoverProvider
                        CompletionOptions(false, ["."]),
                        SignatureHelpOptions(["("]),
                        true, #definitionProvider
                        true, # referencesProvider
                        false, # documentHighlightProvider
                        true, # documentSymbolProvider 
                        true, # workspaceSymbolProvider
                        true, # codeActionProvider
                        # CodeLensOptions(), 
                        true, # documentFormattingProvider
                        false, # documentRangeFormattingProvider
                        # DocumentOnTypeFormattingOptions(), 
                        false, # renameProvider
                        DocumentLinkOptions(false),
                        ExecuteCommandOptions(),
                        nothing)

function process(r::JSONRPC.Request{Val{Symbol("initialize")},InitializeParams}, server)
    if !isnull(r.params.rootUri)
        server.rootPath = uri2filepath(r.params.rootUri.value)
    elseif !isnull(r.params.rootPath)
        server.rootPath = r.params.rootPath.value
    else
        server.rootPath = ""
    end
    
    response = JSONRPC.Response(get(r.id), InitializeResult(serverCapabilities))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("initialize")}}, params)
    return InitializeParams(params)
end


function process(r::JSONRPC.Request{Val{Symbol("initialized")},Dict{String,Any}}, server) 
    if server.rootPath != ""
        for (root, dirs, files) in walkdir(server.rootPath)
            for file in files
                if endswith(file, ".jl")
                    filepath = joinpath(root, file)
                    !isfile(filepath) && continue
                    info("parsed $filepath")
                    uri = string("file://", is_windows() ? string("/", replace(replace(filepath, '\\', '/'), ":", "%3A")) : filepath)
                    content = readstring(filepath)
                    server.documents[uri] = Document(uri, content, true)
                    doc = server.documents[uri]
                    doc._runlinter = false
                    parse_all(doc, server)
                    doc._runlinter = true
                end
            end
            # for (uri, doc) in server.documents
            #     lint(doc, server)
            # end
        end
    end
    server.isrunning = true
end

function JSONRPC.parse_params(::Type{Val{Symbol("initialized")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("shutdown")}}, server) end
function JSONRPC.parse_params(::Type{Val{Symbol("shutdown")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("exit")}}, server) 
    exit()
end
function JSONRPC.parse_params(::Type{Val{Symbol("exit")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    server.documents[uri] = Document(uri, r.params.textDocument.text, false)
    doc = server.documents[uri]
    if startswith(uri, string("file://", server.rootPath))
        doc._workspace_file = true
    end
    set_open_in_editor(doc, true)
    parse_all(doc, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    doc = server.documents[uri]
    empty!(doc.diagnostics)
    publish_diagnostics(doc, server)
    if !is_workspace_file(doc)
        delete!(server.documents, uri)
    else
        set_open_in_editor(doc, false)
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    doc = server.documents[r.params.textDocument.uri]
    doc._version = r.params.textDocument.version
    isempty(r.params.contentChanges) && return
    # dirty = get_offset(doc, last(r.params.contentChanges).range.start.line + 1, last(r.params.contentChanges).range.start.character + 1):get_offset(doc, first(r.params.contentChanges).range.stop.line + 1, first(r.params.contentChanges).range.stop.character + 1)
    # for c in r.params.contentChanges
    #     update(doc, c.range.start.line + 1, c.range.start.character + 1, c.rangeLength, c.text)
    # end
    doc._content = last(r.params.contentChanges).text
    doc._line_offsets = Nullable{Vector{Int}}()
    parse_all(doc, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/cancelRequest")},CancelParams}, server)
    
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")},DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri
        if change._type == FileChangeType_Created || (change._type == FileChangeType_Changed && !get_open_in_editor(server.documents[uri]))
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            server.documents[uri] = Document(uri, content, true)

        elseif change._type == FileChangeType_Deleted && !get_open_in_editor(server.documents[uri])
            delete!(server.documents, uri)

            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), PublishDiagnosticsParams(uri, Diagnostic[]))
            send(response, server)
        end
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWatchedFiles")}}, params)
    return DidChangeWatchedFilesParams(params)
end

function JSONRPC.parse_params(::Type{Val{Symbol("\$/cancelRequest")}}, params)
    return CancelParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")},DidSaveTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    doc = server.documents[uri]
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params)
    
    return DidSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/setTraceNotification")},Dict{String,Any}}, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("\$/setTraceNotification")}}, params)
    return Any(params)
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server)
    if isempty(r.params["settings"])
        server.runlinter = false
        for uri in keys(server.documents)
            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), PublishDiagnosticsParams(uri, Diagnostic[]))
            send(response, server)
        end
    else
        server.runlinter = true
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params)
    return Any(params)
end
