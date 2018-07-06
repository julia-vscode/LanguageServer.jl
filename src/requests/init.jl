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
                        true, # renameProvider
                        DocumentLinkOptions(false),
                        ExecuteCommandOptions(),
                        nothing,
                        WorkspaceOptions(WorkspaceFoldersOptions(true, true)))

hasreadperm(p::String) = (uperm(p) & 0x04) == 0x04

function isjuliabasedir(path)
    fs = readdir(path)
    if "base" in fs && isdir(joinpath(path, "base"))
        return isjuliabasedir(joinpath(path, "base"))
    end
    all(f -> f in fs, ["coreimg.jl", "coreio.jl", "inference.jl"])
end

function load_rootpath(path)
    !(path == "" || 
    path == homedir() ||
    isjuliabasedir(path)) &&
    isdir(path) &&
    hasreadperm(path)
end

function load_folder(wf::WorkspaceFolder, server)
    path = uri2filepath(wf.uri)
    load_folder(path, server)
end

function load_folder(path::String, server)
    if load_rootpath(path)
        for (root, dirs, files) in walkdir(path, onerror = x->x)
            for file in files
                if endswith(file, ".jl")
                    filepath = joinpath(root, file)
                    (!isfile(filepath) || !hasreadperm(filepath)) && continue
                    info("parsed $filepath")
                    uri = filepath2uri(filepath)
                    content = readstring(filepath)
                    server.documents[URI2(uri)] = Document(uri, content, true)
                    doc = server.documents[URI2(uri)]
                    doc._runlinter = false
                    parse_all(doc, server)
                    doc._runlinter = true
                end
            end
        end
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("initialize")}}, params)
    return InitializeParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("initialize")},InitializeParams}, server)
    # Only look at rootUri and rootPath if the client doesn't support workspaceFolders
    if isnull(r.params.capabilities.workspace.workspaceFolders) || get(r.params.capabilities.workspace.workspaceFolders)==false
        if !isnull(r.params.rootUri)
            push!(server.workspaceFolders, uri2filepath(r.params.rootUri.value))
        elseif !isnull(r.params.rootPath)
            push!(server.workspaceFolders,  r.params.rootPath.value)
        end
    else
        for wksp in r.params.workspaceFolders
            push!(server.workspaceFolders, uri2filepath(wksp.uri))
        end
    end
    
    response = JSONRPC.Response(get(r.id), InitializeResult(serverCapabilities))
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("initialized")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("initialized")}}, server)
    server.debug_mode && tic()
    info(server.workspaceFolders)
    for wkspc in server.workspaceFolders
        load_folder(wkspc, server)
    end
    server.debug_mode && info("Startup time: $(toq())")

    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "id" => "278352324", "method" => "client/registerCapability", "params" => Dict("registrations" => [Dict("id"=>"28c6550c-bd7b-11e7-abc4-cec278b6b50a", "method"=>"workspace/didChangeWorkspaceFolders")]))))
end


function JSONRPC.parse_params(::Type{Val{Symbol("shutdown")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("shutdown")}}, server)
    send(nothing, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("exit")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("exit")}}, server) 
    exit()
end
