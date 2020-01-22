const serverCapabilities = ServerCapabilities(
    TextDocumentSyncKinds["Incremental"],
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
        for (root, dirs, files) in walkdir(path, onerror = x->x)
            for file in files
                filepath = joinpath(root, file)
                if isvalidjlfile(filepath)
                    (!isfile(filepath) || !hasreadperm(filepath)) && continue
                    uri = filepath2uri(filepath)
                    if URI2(uri) in keys(server.documents)
                        continue
                    else
                        content = read(filepath, String)
                        server.documents[URI2(uri)] = Document(uri, content, true, server)
                        doc = server.documents[URI2(uri)]
                        parse_all(doc, server)
                    end
                end
            end
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
    elseif r.params.workspaceFolders !== nothing
        for wksp in r.params.workspaceFolders
            push!(server.workspaceFolders, uri2filepath(wksp.uri))
        end
    end

    response = JSONRPC.Response(r.id, InitializeResult(serverCapabilities))
    send(response, server)
end


JSONRPC.parse_params(::Type{Val{Symbol("initialized")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("initialized")}}, server)
    if server.workspaceFolders !== nothing
        for wkspc in server.workspaceFolders
            load_folder(wkspc, server)
        end
    end
    request_julia_config(server)

    send(Dict("jsonrpc" => "2.0", "id" => "278352324", "method" => "client/registerCapability", "params" => Dict("registrations" => [Dict("id"=>"28c6550c-bd7b-11e7-abc4-cec278b6b50a", "method"=>"workspace/didChangeWorkspaceFolders")])), server)
end


JSONRPC.parse_params(::Type{Val{Symbol("shutdown")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("shutdown")}}, server)
    send(nothing, server)
end

JSONRPC.parse_params(::Type{Val{Symbol("exit")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("exit")}}, server) 
    exit()
end
