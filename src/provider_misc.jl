const TextDocumentSyncKind = Dict("None"=>0, "Full"=>1, "Incremental"=>2)



const serverCapabilities = ServerCapabilities(
                        TextDocumentSyncKind["Incremental"],
                        true, #hoverProvider
                        CompletionOptions(false,["."]),
                        true, #definitionProvider
                        SignatureHelpOptions(["("]),
                        true) # documentSymbolProvider 

function process(r::JSONRPC.Request{Val{Symbol("initialize")},Dict{String,Any}}, server)
    server.rootPath=haskey(r.params,"rootPath") ? r.params["rootPath"] : ""
    if server.rootPath!=""
        for (root, dirs, files) in walkdir(server.rootPath)
            for file in files
                if splitext(file)[2]==".jl"
                    filepath = joinpath(root, file)
                    uri = string("file://", is_windows() ? string("/", replace(replace(filepath, '\\', '/'), ":", "%3A")) : filepath)
                    content = String(read(filepath))
                    server.documents[uri] = Document(uri, content, true)
                end
            end
        end
    end
    response = JSONRPC.Response(get(r.id), InitializeResult(serverCapabilities))
    send(response, server)

    env_new = copy(ENV)
    env_new["JULIA_PKGDIR"] = server.user_pkg_dir

    cache_jl_path = replace(joinpath(dirname(@__FILE__), "cache.jl"), "\\", "\\\\")
    
    o,i, p = readandwrite(Cmd(`$JULIA_HOME/julia -e "include(\"$cache_jl_path\");
    top=Dict();
    modnames(Main, top);
    io = IOBuffer();
    io_base64 = Base64EncodePipe(io);
    serialize(io_base64, top);
    close(io_base64);
    str = takebuf_string(io);
    println(STDOUT, str);
    "`, env=env_new))

    @async begin
        str = readline(o)
        data = base64decode(str)
        mods = deserialize(IOBuffer(data))
        for k in keys(mods)
            if !(k in keys(server.cache))
                server.cache[k] = mods[k]
            end
        end
        info("Base cache loaded")
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("initialize")}}, params)
    return Any(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    if !haskey(server.documents, uri)
        server.documents[uri] = Document(uri, r.params.textDocument.text, false)
    end
    doc = server.documents[uri]
    set_open_in_editor(doc, true)

    parseblocks(doc, server)
    
    if should_file_be_linted(r.params.textDocument.uri, server) 
        process_diagnostics(r.params.textDocument.uri, server) 
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
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

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    doc = server.documents[r.params.textDocument.uri]
    blocks = server.documents[r.params.textDocument.uri].blocks
    dirty = (last(r.params.contentChanges).range.start.line+1, last(r.params.contentChanges).range.start.character+1, first(r.params.contentChanges).range.stop.line+1, first(r.params.contentChanges).range.stop.character+1)
    for c in r.params.contentChanges
        update(doc, c.range.start.line+1, c.range.start.character+1, c.rangeLength, c.text)
    end
    if should_file_be_linted(r.params.textDocument.uri, server) 
        process_diagnostics(r.params.textDocument.uri, server) 
    end
    parseblocks(doc, server, dirty...) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/cancelRequest")},CancelParams}, server)
    
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")},DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri
        if change._type==FileChangeType_Created || (change._type==FileChangeType_Changed && !get_open_in_editor(server.documents[uri]))
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            server.documents[uri] = Document(uri, content, true)

            if should_file_be_linted(uri, server)
                process_diagnostics(uri, server)
            end
        elseif change._type==FileChangeType_Deleted && !get_open_in_editor(server.documents[uri])
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
    parseblocks(server.documents[uri], server)
    if should_file_be_linted(r.params.textDocument.uri, server) 
        process_diagnostics(r.params.textDocument.uri, server) 
    end
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
        server.runlinter=false
        for uri in keys(server.documents)
            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), PublishDiagnosticsParams(uri, Diagnostic[]))
            send(response, server)
        end
    else
        server.runlinter=true
        for uri in keys(server.documents)
            process_diagnostics(uri, server)
        end
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params)
    return Any(params)
end