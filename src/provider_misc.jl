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
    response = JSONRPC.Response(get(r.id), InitializeResult(serverCapabilities))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("initialize")}}, params)
    return Any(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    server.documents[r.params.textDocument.uri] = Document(r.params.textDocument.text)
    parseblocks(r.params.textDocument.uri, server)
    
    if should_file_be_linted(r.params.textDocument.uri, server) 
        process_diagnostics(r.params.textDocument.uri, server) 
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
    delete!(server.documents, r.params.textDocument.uri)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    doc = server.documents[r.params.textDocument.uri]
    blocks = server.documents[r.params.textDocument.uri].blocks
    for c in r.params.contentChanges
        update(doc, c.range.start.line+1, c.range.start.character+1, c.rangeLength, c.text)
        
        for i = 1:length(blocks)
            intersect(blocks[i].range, c.range) && (blocks[i].uptodate = false)
        end
    end
    parseblocks(r.params.textDocument.uri, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/cancelRequest")},CancelParams}, server)
    
end


function JSONRPC.parse_params(::Type{Val{Symbol("\$/cancelRequest")}}, params)
    return CancelParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")},DidSaveTextDocumentParams}, server)
    parseallblocks(r.params.textDocument.uri, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params)
    
    return DidSaveTextDocumentParams(params)
end