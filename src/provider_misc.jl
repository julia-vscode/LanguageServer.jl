const TextDocumentSyncKind = Dict("None" => 0, "Full" => 1, "Incremental" => 2)

const serverCapabilities = ServerCapabilities(
                        TextDocumentSyncKind["Incremental"],
                        true, #hoverProvider
                        CompletionOptions(false, ["."]),
                        SignatureHelpOptions(["("]),
                        true, #definitionProvider
                        true, # referencesProvider
                        false, # documentHighlightProvider
                        true, # documentSymbolProvider 
                        true, # workspaceSymbolProvider
                        false, # codeActionProvider
                        # CodeLensOptions(), 
                        false, # documentFormattingProvider
                        false, # documentRangeFormattingProvider
                        # DocumentOnTypeFormattingOptions(), 
                        false, # renameProvider
                        DocumentLinkOptions(false),
                        ExecuteCommandOptions(),
                        nothing)

function process(r::JSONRPC.Request{Val{Symbol("initialize")}, InitializeParams}, server)
    put!(server.user_modules, :Main)
    # server.cache[:Base] = Dict(:EXPORTEDNAMES => [])
    # server.cache[:Core] = Dict(:EXPORTEDNAMES => [])
    
    if !isnull(r.params.rootUri )
        server.rootPath = uri2filepath(r.params.rootUri)
    elseif !isnull(r.params.rootPath)
        server.rootPath = r.params.rootPath
    else
        server.rootPath = ""
    end
    
    if server.rootPath != ""
        for (root, dirs, files) in walkdir(server.rootPath)
            for file in files
                if endswith(file, ".jl")
                    info("parsed $file")
                    filepath = joinpath(root, file)
                    uri = string("file://", is_windows() ? string("/", replace(replace(filepath, '\\', '/'), ":", "%3A")) : filepath)
                    content = readstring(filepath)
                    server.documents[uri] = Document(uric, content, true)
                    parse_diag(server.documents[uri], server)
                end
            end
        end
    end
    response = JSONRPC.Response(get(r.id), InitializeResult(serverCapabilities))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("initialize")}}, params)
    return InitializeParams(params)
end


function process(r::JSONRPC.Request{Val{Symbol("initialized")}, Dict{String, Any}}, server) end

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

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")}, DidOpenTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    if !haskey(server.documents, uri)
        server.documents[uri] = Document(uri, r.params.textDocument.text, false)
    end
    doc = server.documents[uri]
    set_open_in_editor(doc, true)

    parse_diag(server.documents[uri], server)
    
    if should_file_be_linted(r.params.textDocument.uri, server) 
        process_diagnostics(r.params.textDocument.uri, server) 
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")}, DidCloseTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    if !is_workspace_file(server.documents[uri])
        delete!(server.documents, uri)
    else
        set_open_in_editor(server.documents[uri], false)
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")}, DidChangeTextDocumentParams}, server)
    doc = server.documents[r.params.textDocument.uri]
    blocks = server.documents[r.params.textDocument.uri].code
    dirty = (last(r.params.contentChanges).range.start.line + 1, last(r.params.contentChanges).range.start.character + 1, first(r.params.contentChanges).range.stop.line + 1, first(r.params.contentChanges).range.stop.character + 1)
    for c in r.params.contentChanges
        update(doc, c.range.start.line + 1, c.range.start.character + 1, c.rangeLength, c.text)
    end
    parse_diag(doc, server)
    
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/cancelRequest")}, CancelParams}, server)
    
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")}, DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri
        if change._type == FileChangeType_Created || (change._type == FileChangeType_Changed && !get_open_in_editor(server.documents[uri]))
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            server.documents[uri] = Document(uri, content, true)

            if should_file_be_linted(uri, server)
                process_diagnostics(uri, server)
            end
        elseif change._type == FileChangeType_Deleted && !get_open_in_editor(server.documents[uri])
            delete!(server.documents, uri)

            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")}, PublishDiagnosticsParams}(Nullable{Union{String, Int64}}(), PublishDiagnosticsParams(uri, Diagnostic[]))
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

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")}, DidSaveTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    doc = server.documents[uri]
    parse_diag(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params)
    
    return DidSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/setTraceNotification")}, Dict{String, Any}}, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("\$/setTraceNotification")}}, params)
    return Any(params)
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")}, Dict{String, Any}}, server)
    if isempty(r.params["settings"])
        server.runlinter = false
        for uri in keys(server.documents)
            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")}, PublishDiagnosticsParams}(Nullable{Union{String, Int64}}(), PublishDiagnosticsParams(uri, Diagnostic[]))
            send(response, server)
        end
    else
        server.runlinter = true
        for uri in keys(server.documents)
            process_diagnostics(uri, server)
        end
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params)
    return Any(params)
end