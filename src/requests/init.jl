const serverCapabilities = ServerCapabilities(
    # TextDocumentSyncKinds["Incremental"],
    TextDocumentSyncOptions(true, TextDocumentSyncKinds["Incremental"], false, false, SaveOptions(true)),
    true,
    CompletionOptions(false, ["."]),
    SignatureHelpOptions(["(", ","]),
    true,
    false,
    false,
    true,
    false,
    true,
    true,
    true,
    missing,
    true,
    false,
    missing,
    true,
    missing,
    false,
    false,
    false,
    ExecuteCommandOptions(String[
        "ExplicitPackageVarImport",
        "ExpandFunction",
        "AddDefaultConstructor",
        "ReexportModule",
        # "WrapIfBlock"
        ]),
    WorkspaceOptions(WorkspaceFoldersOptions(true, true)),
    missing)

hasreadperm(p::String) = (uperm(p) & 0x04) == 0x04

function isjuliabasedir(path)
    fs = readdir(path)
    if "base" in fs && isdir(joinpath(path, "base"))
        return isjuliabasedir(joinpath(path, "base"))
    end
    all(f -> f in fs, ["coreimg.jl", "coreio.jl", "inference.jl"])
end

function has_too_many_files(path, N = 5000)
    i = 0

    try
        for (root, dirs, files) in walkdir(path, onerror = x->x)
            for file in files
                if endswith(file, ".jl")
                    i += 1
                end
                if i > N
                    @info "Your workspace folder has > $N Julia files, server will not try to load them."
                    return true
                end
            end
        end
    catch err
        isa(err, Base.IOError) || rethrow()
        return false
    end

    return false
end

function load_rootpath(path)
    isdir(path) &&
    hasreadperm(path) &&
    path != "" &&
    path != homedir() &&
    !isjuliabasedir(path) &&
    !has_too_many_files(path)
end

function load_folder(wf::WorkspaceFolder, server)
    path = uri2filepath(wf.uri)
    load_folder(path, server)
end

function load_folder(path::String, server)
    if load_rootpath(path)
        try
            for (root, dirs, files) in walkdir(path, onerror = x->x)
                for file in files
                    filepath = joinpath(root, file)
                    if isvalidjlfile(filepath)
                        uri = filepath2uri(filepath)
                        if hasdocument(server, URI2(uri))
                            set_is_workspace_file(getdocument(server, URI2(uri)), true)
                            continue
                        else
                            content = try
                                s = read(filepath, String)
                                isvalid(s) || continue
                                s
                            catch err
                                isa(err, Base.IOError) || rethrow()
                                continue
                            end
                            doc = Document(uri, content, true, server)
                            setdocument!(server, URI2(uri), doc)
                            parse_all(doc, server)
                        end
                    end
                end
            end
        catch err
            isa(err, Base.IOError) || rethrow()
        end
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("initialize")}}, params) = InitializeParams(params)
function process(r::JSONRPC.Request{Val{Symbol("initialize")},InitializeParams}, server)
    # Only look at rootUri and rootPath if the client doesn't support workspaceFolders
    if ismissing(r.params.capabilities.workspace.workspaceFolders) || r.params.capabilities.workspace.workspaceFolders == false
        if !(r.params.rootUri isa Nothing)
            push!(server.workspaceFolders, uri2filepath(r.params.rootUri))
        elseif !(r.params.rootPath isa Nothing)
            push!(server.workspaceFolders,  r.params.rootPath)
        end
    elseif (r.params.workspaceFolders !== nothing) & (r.params.workspaceFolders !== missing)
        for wksp in r.params.workspaceFolders
            push!(server.workspaceFolders, uri2filepath(wksp.uri))
        end
    end
    
    if !ismissing(r.params.capabilities.window) && get(r.params.capabilities.window, "workDoneProgress", false)
        server.clientcapability_window_workdoneprogress = true
    else
        server.clientcapability_window_workdoneprogress = false
    end

    return InitializeResult(serverCapabilities)
end


JSONRPC.parse_params(::Type{Val{Symbol("initialized")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("initialized")}}, server)
    server.status=:running

    if server.workspaceFolders !== nothing
        for wkspc in server.workspaceFolders
            load_folder(wkspc, server)
        end
    end
    request_julia_config(server)
    
    JSONRPCEndpoints.send_request(server.jr_endpoint, "client/registerCapability", Dict("registrations" => [Dict("id"=>"28c6550c-bd7b-11e7-abc4-cec278b6b50a", "method"=>"workspace/didChangeWorkspaceFolders")]))

    if server.number_of_outstanding_symserver_requests > 0
        create_symserver_progress_ui(server)
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("shutdown")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("shutdown")}}, server)
    return nothing
end

JSONRPC.parse_params(::Type{Val{Symbol("exit")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("exit")}}, server::LanguageServerInstance) 
    server.symbol_server.process isa Base.Process && kill(server.symbol_server.process)
    exit()
end
