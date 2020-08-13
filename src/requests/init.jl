const serverCapabilities = ServerCapabilities(
    TextDocumentSyncOptions(true,
    TextDocumentSyncKinds.Full,
    false,
    false,
    SaveOptions(true)),
    CompletionOptions(false, [".", "@", "\"", "^"], missing),
    true,
    SignatureHelpOptions(["(", ","], missing),
    false,
    true,
    false,
    false,
    true,
    false,
    true,
    true,
    missing,
    missing,
    false,
    true,
    false,
    missing,
    true,
    false,
    ExecuteCommandOptions(missing, String["ExplicitPackageVarImport", "ExpandFunction", "AddDefaultConstructor", "ReexportModule", "FixMissingRef"]),
    false,
    true,
    WorkspaceOptions(WorkspaceFoldersOptions(true, true)),
    missing)

hasreadperm(p::String) = (uperm(p) & 0x04) == 0x04

function isjuliabasedir(path)
    try
        fs = readdir(path)
        if "base" in fs && isdir(joinpath(path, "base"))
            return isjuliabasedir(joinpath(path, "base"))
        end
        return all(f->f in fs, ["coreimg.jl", "coreio.jl", "inference.jl"])
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return false
    end
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
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return false
    end

    return false
end

function load_rootpath(path)
    try
        return isdir(path) &&
            hasreadperm(path) &&
            path != "" &&
            path != homedir() &&
            !isjuliabasedir(path) &&
            !has_too_many_files(path)
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return false
    end
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
                                isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
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
            isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        end
    end
end


function initialize_request(params::InitializeParams, server::LanguageServerInstance, conn)
    # Only look at rootUri and rootPath if the client doesn't support workspaceFolders
    if ismissing(params.capabilities.workspace.workspaceFolders) || params.capabilities.workspace.workspaceFolders == false
        if !(params.rootUri isa Nothing)
            push!(server.workspaceFolders, uri2filepath(params.rootUri))
        elseif !(params.rootPath isa Nothing)
            push!(server.workspaceFolders,  params.rootPath)
        end
    elseif (params.workspaceFolders !== nothing) & (params.workspaceFolders !== missing)
        for wksp in params.workspaceFolders
            if wksp.uri !== nothing
                push!(server.workspaceFolders, uri2filepath(wksp.uri))
            end
        end
    end

    server.clientCapabilities = params.capabilities
    server.clientInfo = params.clientInfo

    if !ismissing(params.capabilities.window) && params.capabilities.window.workDoneProgress
        server.clientcapability_window_workdoneprogress = true
    else
        server.clientcapability_window_workdoneprogress = false
    end

    if !ismissing(params.capabilities.workspace.didChangeConfiguration) &&
        !ismissing(params.capabilities.workspace.didChangeConfiguration.dynamicRegistration) &&
        params.capabilities.workspace.didChangeConfiguration.dynamicRegistration

        server.clientcapability_workspace_didChangeConfiguration = true
    end

    return InitializeResult(serverCapabilities, missing)
end


function initialized_notification(params::InitializedParams, server::LanguageServerInstance, conn)
    server.status = :running

    if server.clientcapability_workspace_didChangeConfiguration
        JSONRPC.send(
            conn,
            client_registerCapability_request_type,
            RegistrationParams([Registration(string(uuid4()), "workspace/didChangeConfiguration", missing)])
        )
    end

    if server.workspaceFolders !== nothing
        for wkspc in server.workspaceFolders
            load_folder(wkspc, server)
        end
    end
    request_julia_config(server, conn)

    if server.number_of_outstanding_symserver_requests > 0
        create_symserver_progress_ui(server)
    end
end

# TODO provide type for params
function shutdown_request(params, server::LanguageServerInstance, conn)
    return nothing
end

# TODO provide type for params
function exit_notification(params, server::LanguageServerInstance, conn)
    server.symbol_server.process isa Base.Process && kill(server.symbol_server.process)
    exit()
end
