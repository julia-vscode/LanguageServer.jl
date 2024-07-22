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

function load_folder(wf::WorkspaceFolder, server, added_docs)
    path = uri2filepath(wf.uri)
    load_folder(path, server, added_docs)
end

function load_folder(path::String, server, added_docs)
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
                                push!(added_docs, doc)
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

    JuliaWorkspaces.mark_current_diagnostics(server.workspace)
    JuliaWorkspaces.mark_current_testitems(server.workspace)
    added_docs = Document[]

    if server.workspaceFolders !== nothing
        for i in server.workspaceFolders
            files = JuliaWorkspaces.read_path_into_textdocuments(filepath2uri(i), ignore_io_errors=true)

            for i in files
                # This might be a sub folder of a folder that is already watched
                # so we make sure we don't have duplicates
                if !haskey(server._files_from_disc, i.uri)
                    server._files_from_disc[i.uri] = i

                    if !haskey(server._open_file_versions, i.uri)
                        JuliaWorkspaces.add_file!(server.workspace, i)
                    end
                end
            end
        end

        # Add project files separately in case they are not in a workspace folder
        if server.env_path != ""
            for file in ["Project.toml", "JuliaProject.toml", "Manifest.toml", "JuliaManifest.toml"]
                file_full_path = joinpath(server.env_path, file)
                uri = filepath2uri(file_full_path)
                if isfile(file_full_path)
                    # Only add again if outside of the workspace folders
                    if all(i->!startswith(file_full_path, i), server.workspaceFolders)
                        if haskey(server._files_from_disc, uri)
                            error("This should not happen")
                        end

                        text_file = JuliaWorkspaces.read_text_file_from_uri(uri, return_nothing_on_io_error=true)
                        text_file === nothing || continue

                        server._files_from_disc[uri] = text_file

                        if !haskey(server._open_file_versions, uri)
                            JuliaWorkspaces.add_file!(server.workspace, text_file)
                        end
                    end
                    # But we do want to track, in case the workspace folder is removed
                    push!(server._extra_tracked_files, filepath2uri(file_full_path))
                end
            end
        end

        JuliaWorkspaces.set_input_fallback_test_project!(server.workspace.runtime, isempty(server.env_path) ? nothing : filepath2uri(server.env_path))

        for wkspc in server.workspaceFolders
            load_folder(wkspc, server, added_docs)
        end

        for doc in added_docs
            lint!(doc, server)
        end
    end

    publish_diagnostics(get_uri.(added_docs), server, conn, "initialized_notification")
    publish_tests(server)

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
