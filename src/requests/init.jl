function ServerCapabilities(client::ClientCapabilities)
    prepareSupport = !ismissing(client.textDocument) && !ismissing(client.textDocument.rename) && client.textDocument.rename.prepareSupport === true

    ServerCapabilities(
        TextDocumentSyncOptions(
            true,
            TextDocumentSyncKinds.Incremental,
            false,
            false,
            SaveOptions(true)
        ),
        CompletionOptions(false, [".", "@", "\"", "^"], missing),
        true,
        SignatureHelpOptions(["(", ","], missing),
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        missing,
        DocumentLinkOptions(false, missing),
        false,
        true,
        true,
        missing,
        RenameOptions(missing, prepareSupport),
        false,
        ExecuteCommandOptions(missing, collect(keys(LSActions))),
        true,
        true,
        true,
        WorkspaceOptions(WorkspaceFoldersOptions(true, true)),
        missing
    )

end

hasreadperm(p::String) = (uperm(p) & 0x04) == 0x04

function isjuliabasedir(path)
    try
        fs = readdir(path)
        if "base" in fs && isdir(joinpath(path, "base"))
            return isjuliabasedir(joinpath(path, "base"))
        end
        return all(f -> f in fs, ["coreimg.jl", "coreio.jl", "inference.jl"])
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return false
    end
end

function has_too_many_files(path, N=5000)
    i = 0

    try
        for (_, _, files) in walkdir(path, onerror=x -> x)
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
        is_walkdir_error(err) || rethrow()
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
        is_walkdir_error(err) || rethrow()
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
            for (root, _, files) in walkdir(path, onerror=x -> x)
                for file in files
                    filepath = joinpath(root, file)
                    if isvalidjlfile(filepath)
                        uri = filepath2uri(filepath)
                        if hasdocument(server, uri)
                            set_is_workspace_file(getdocument(server, uri), true)
                            continue
                        else
                            content = try
                                s = read(filepath, String)
                                our_isvalid(s) || continue
                                s
                            catch err
                                is_walkdir_error(err) || rethrow()
                                continue
                            end
                            doc = Document(TextDocument(uri, content, 0), true, server)
                            setdocument!(server, uri, doc)
                            try
                                parse_all(doc, server)
                            catch ex
                                @error "Error parsing file $(uri)"
                                rethrow()
                            end
                        end
                    end
                end
            end
        catch err
            is_walkdir_error(err) || rethrow()
        end
    end
end

is_walkdir_error(_) = false
is_walkdir_error(::Base.IOError) = true
is_walkdir_error(::Base.SystemError) = true
@static if VERSION > v"1.3.0-"
    is_walkdir_error(err::Base.TaskFailedException) = is_walkdir_error(err.task.exception)
end

function initialize_request(params::InitializeParams, server::LanguageServerInstance, conn)
    # Only look at rootUri and rootPath if the client doesn't support workspaceFolders
    if !ismissing(params.capabilities.workspace) && (ismissing(params.capabilities.workspace.workspaceFolders) || params.capabilities.workspace.workspaceFolders == false)
        if !(params.rootUri isa Nothing)
            push!(server.workspaceFolders, uri2filepath(params.rootUri))
        elseif !(params.rootPath isa Nothing)
            push!(server.workspaceFolders,  params.rootPath)
        end
    elseif (params.workspaceFolders !== nothing) & (params.workspaceFolders !== missing)
        for wksp in params.workspaceFolders
            if wksp.uri !== nothing
                fpath = uri2filepath(wksp.uri)
                if fpath !== nothing
                    push!(server.workspaceFolders, fpath)
                end
            end
        end
    end

    server.clientCapabilities = params.capabilities
    server.clientInfo = params.clientInfo
    server.editor_pid = params.processId

    if !ismissing(params.capabilities.window) && !ismissing(params.capabilities.window.workDoneProgress) && params.capabilities.window.workDoneProgress
        server.clientcapability_window_workdoneprogress = true
    else
        server.clientcapability_window_workdoneprogress = false
    end

    if !ismissing(params.capabilities.workspace) &&
        !ismissing(params.capabilities.workspace.didChangeConfiguration) &&
        !ismissing(params.capabilities.workspace.didChangeConfiguration.dynamicRegistration) &&
        params.capabilities.workspace.didChangeConfiguration.dynamicRegistration

        server.clientcapability_workspace_didChangeConfiguration = true
    end

    if !ismissing(params.initializationOptions) && params.initializationOptions !== nothing
        server.initialization_options = params.initializationOptions
    end

    return InitializeResult(ServerCapabilities(server.clientCapabilities), missing)
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
        for i in server.workspaceFolders
            JuliaWorkspaces.add_folder_from_disc!(server.workspace, i)
        end

        # Add project files separately in case they are not in a workspace folder
        if server.env_path != ""
            for file in ["Project.toml", "JuliaProject.toml", "Manifest.toml", "JuliaManifest.toml"]
                file_full_path = joinpath(server.env_path, file)
                if isfile(file_full_path)
                    JuliaWorkspace.add_file_from_disc!(server.workspace, file_full_path)
                end
            end
        end

        for wkspc in server.workspaceFolders
            load_folder(wkspc, server)
        end
    end

    request_julia_config(server, conn)

    if server.number_of_outstanding_symserver_requests > 0
        create_symserver_progress_ui(server)
    end
end

function shutdown_request(params::Nothing, server::LanguageServerInstance, conn)
    server.shutdown_requested = true
    return nothing
end

function exit_notification(params::Nothing, server::LanguageServerInstance, conn)
    server.symbol_server.process isa Base.Process && kill(server.symbol_server.process)
    exit(server.shutdown_requested ? 0 : 1)
end
