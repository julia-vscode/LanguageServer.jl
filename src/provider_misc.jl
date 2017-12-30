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

function JSONRPC.parse_params(::Type{Val{Symbol("initialize")}}, params)
    return InitializeParams(params)
end

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
    isdir(path)
end

function load_folder(wf::WorkspaceFolder, server)
    path = uri2filepath(wf.uri)
    load_folder(path, server)
end

function load_folder(path::String, server)
    if load_rootpath(path)
        for (root, dirs, files) in walkdir(path)
            for file in files
                if endswith(file, ".jl")
                    filepath = joinpath(root, file)
                    !isfile(filepath) && continue
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

function process(r::JSONRPC.Request{Val{Symbol("initialized")}}, server)
    server.debug_mode && tic()
    # if load_rootpath(server.rootPath)
    #     for (root, dirs, files) in walkdir(server.rootPath)
    #         for file in files
    #             if endswith(file, ".jl")
    #                 filepath = joinpath(root, file)
    #                 !isfile(filepath) && continue
    #                 info("parsed $filepath")
    #                 uri = filepath2uri(filepath)
    #                 content = readstring(filepath)
    #                 server.documents[URI2(uri)] = Document(uri, content, true)
    #                 doc = server.documents[URI2(uri)]
    #                 doc._runlinter = false
    #                 parse_all(doc, server)
    #                 doc._runlinter = true
    #             end
    #         end
    #     end
    # end
    info(server.workspaceFolders)
    for wkspc in server.workspaceFolders
        load_folder(wkspc, server)
    end
    server.debug_mode && info("Startup time: $(toq())")

    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "id" => "278352324", "method" => "client/registerCapability", "params" => Dict("registrations" => [Dict("id"=>"28c6550c-bd7b-11e7-abc4-cec278b6b50a", "method"=>"workspace/didChangeWorkspaceFolders")]))), server.debug_mode)
end

function JSONRPC.parse_params(::Type{Val{Symbol("initialized")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("shutdown")}}, server)
    send(nothing, server)
end
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
    server.isrunning = true
    uri = r.params.textDocument.uri
    server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false)
    doc = server.documents[URI2(uri)]
    if any(i->startswith(uri, filepath2uri(i)), server.workspaceFolders)
        doc._workspace_file = true
    end
    set_open_in_editor(doc, true)
    if is_ignored(uri, server)
        doc._runlinter = false
    end
    parse_all(doc, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    !haskey(server.documents, URI2(uri)) && return
    doc = server.documents[URI2(uri)]
    empty!(doc.diagnostics)
    publish_diagnostics(doc, server)
    if !is_workspace_file(doc)
        delete!(server.documents, URI2(uri))
    else
        set_open_in_editor(doc, false)
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    doc = server.documents[URI2(r.params.textDocument.uri)]
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
        !haskey(server.documents, URI2(uri)) && continue
        if change._type == FileChangeType_Created || (change._type == FileChangeType_Changed && !get_open_in_editor(server.documents[URI2(uri)]))
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            server.documents[URI2(uri)] = Document(uri, content, true)
            parse_all(server.documents[URI2(uri)], server)

        elseif change._type == FileChangeType_Deleted && !get_open_in_editor(server.documents[URI2(uri)])
            delete!(server.documents, URI2(uri))

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
    doc = server.documents[URI2(uri)]
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


function clear_diagnostics(uri::URI2, server)
    doc = server.documents[uri]
    empty!(doc.diagnostics)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), PublishDiagnosticsParams(doc._uri, Diagnostic[]))
    send(response, server)

end

function clear_diagnostics(server)
    for (uri, doc) in server.documents
        clear_diagnostics(uri, server)
    end
end


function is_ignored(uri, server)
    fpath = uri2filepath(uri)
    fpath in server.ignorelist && return true
    for ig in server.ignorelist
        if !endswith(ig, ".jl")        
            if startswith(fpath, ig)
                return true
            end
        end
    end
    return false
end

is_ignored(uri::URI2, server) = is_ignored(uri._uri, server)
    


function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server)
    if haskey(r.params["settings"], "julia")
        jsettings = r.params["settings"]["julia"]
        if haskey(jsettings, "runlinter") && jsettings["runlinter"] != server.runlinter
            server.runlinter = !server.runlinter
            if server.runlinter
                if !server.isrunning
                    for doc in values(server.documents)
                        doc.diagnostics = lint(doc, server).diagnostics
                        publish_diagnostics(doc, server)
                    end
                end
            else
                clear_diagnostics(server)
            end
        end
        if haskey(jsettings, "lintIgnoreList")
            server.ignorelist = Set(jsettings["lintIgnoreList"])
            for (uri,doc) in server.documents
                if is_ignored(uri, server)
                    doc._runlinter = false
                    clear_diagnostics(uri, server)
                else
                    if !doc._runlinter
                        doc._runlinter = true
                        L = lint(doc, server)
                        append!(doc.diagnostics, L.diagnostics)
                        publish_diagnostics(doc, server)
                    end
                end
            end

        end
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params)
    return Any(params)
end


function process(r::JSONRPC.Request{Val{Symbol("julia/lint-package")},Void}, server)
    warnings = []
    # if isdir(server.rootPath) && "REQUIRE" in readdir(server.rootPath)
    #     topfiles = []
    #     rootUri = is_windows() ? string("file:///", replace(joinpath(replace(server.rootPath, "\\", "/"), "src"), ":", "%3A")) : joinpath("file://", server.rootPath, "src")
    #     for (uri, doc) in server.documents
    #         if startswith(uri, rootUri)
    #             tf, ns = LanguageServer.findtopfile(uri, server)
    #             push!(topfiles, last(tf))
    #         end
    #     end
    #     topfiles = unique(topfiles)
    #     # get all imports and module declarations
    #     import_stmts = []
    #     datatypes = []
    #     functions = []
    #     modules = Union{Symbol,Expr}[]
    #     module_decl = Union{Symbol,Expr}[]
    #     allsymbols = []
    #     for uri in topfiles
    #         s = toplevel(server.documents[uri], server)
    #         for (v, loc, uri1) in s.imports
    #             push!(modules, v.args[1])
    #             push!(import_stmts, (v, loc, uri))
    #         end
    #         for (v, loc, uri1) in s.symbols
    #             if v.t == :module
    #                 push!(module_decl, v.id)
    #             elseif v.t == :mutable || v.t == :immutable || v.t == :abstract || v.t == :bitstype
    #                 push!(datatypes, (v, loc, uri))
    #             elseif v.t == :Function
    #                 push!(functions, (v, loc, uri))
    #             end
    #         end
    #     end
    #     modules = setdiff(unique(modules), vcat([:Base, :Core], unique(module_decl)))

    #     # NEEDS FIX: checking pkg availability/version requires updated METADATA
    #     # avail = Pkg.available()
        
    #     req = get_REQUIRE(server)
    #     rmid = Int[]
    #     for (r, ver) in req
    #         if r == :julia
    #             # NEEDS FIX
    #         else
    #             # if !(String(r) in avail)
    #             #     push!(warnings, "$r declared in REQUIRE but not available in METADATA")
    #             # else
    #             #     avail_ver = Pkg.available(String(r))
    #             #     if !(ver in avail_ver) && ver > VersionNumber(0)
    #             #         push!(warnings, "$r declared in REQUIRE but version $ver not available")
    #             #     end
    #             # end
    #             mloc = findfirst(z -> z == r, modules)
    #             if mloc > 0
    #                 push!(rmid, mloc)
    #             else
    #                 push!(warnings, "$r declared in REQUIRE but doesn't appear to be used.")
    #             end
    #             if r == :Compat && ver == VersionNumber(0)
    #                 push!(warnings, "Compat specified in REQUIRE without specific version.")
    #             end
    #         end
    #     end
    #     deleteat!(modules, rmid)
    #     for m in modules
    #         push!(warnings, "$m used in code but not specified in REQUIRE")
    #     end
    # end
    # for w in warnings
    #     response = JSONRPC.Notification{Val{Symbol("window/showMessage")},ShowMessageParams}(ShowMessageParams(3, w))
    #     send(response, server)
    # end
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/lint-package")}}, params)
    return 
end


# function get_REQUIRE(server)
#     str = readlines(joinpath(server.rootPath, "REQUIRE"))
#     req = Tuple{Symbol,VersionNumber}[]
    
#     for line in str
#         m = (split(line, " "))
#         if length(m) == 2
#             push!(req, (Symbol(m[1]), VersionNumber(m[2])))
#         else
#             push!(req, (Symbol(m[1]), VersionNumber(0)))
#         end
#     end
#     return req
# end


function process(r::JSONRPC.Request{Val{Symbol("julia/toggle-lint")},TextDocumentIdentifier}, server)
    doc = server.documents[URI2(r.uri)]
    doc._runlinter = !doc._runlinter
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggle-lint")}}, params)
    return TextDocumentIdentifier(params["textDocument"])
end


function process(r::JSONRPC.Request{Val{Symbol("julia/reload-modules")},Void}, server)
    reloaded = String[]
    failedtoreload = String[]
    for m in names(Main)
        if isdefined(Main, m) && getfield(Main, m) isa Module
            M = getfield(Main, m)
            if !(m in [:Base, :Core, :Main])
                try
                    reload(string(m))
                    push!(reloaded, string(m))
                catch e
                    push!(failedtoreload, string(m))
                end
            end
        end
    end
    
    response = JSONRPC.Notification{Val{Symbol("window/showMessage")},ShowMessageParams}(ShowMessageParams(3, "Julia: Reloaded modules."))
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/reload-modules")}}, params)
    return
end

function toggle_file_lint(doc, server)
    if doc._runlinter
        doc._runlinter = false
        empty!(doc.diagnostics)
    else
        doc._runlinter = true
        L = lint(doc, server)
        doc.diagnostics = L.diagnostics
    end
    publish_diagnostics(doc, server)
end
function process(r::JSONRPC.Request{Val{Symbol("julia/toggleFileLint")}}, server)
    path = r.params["path"]
    uri = r.params["external"]
    if isdir(uri2filepath(path))
        for doc in values(server.documents)
            uri2 = doc._uri
            server.debug_mode && info("LINT: ignoring $path")
            if startswith(uri2, uri)
                toggle_file_lint(doc, server)
            end
        end
    else
        if uri in map(i->i._uri, values(server.documents))
            server.debug_mode && info("LINT: ignoring $path")
            doc = server.documents[URI2(uri)]
            toggle_file_lint(doc, server)
        end
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggleFileLint")}}, params)
    return params
end


function process(r::JSONRPC.Request{Val{Symbol("julia/toggle-log")},Void}, server)
    server.debug_mode = !server.debug_mode
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggle-log")}}, params)
    return
end

function process(r::JSONRPC.Request{Val{Symbol("julia/getCurrentBlockOffsetRange")}}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end 
    tdpp = r.params
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    i = 0
    p1 = p2 = p3 = 0
    for x in doc.code.ast.args
        if i < offset <= i + x.fullspan
            p1, p2, p3 = i, i + length(x.span), i + x.fullspan
            break
        end
        i += x.fullspan
    end
    y, s = scope(doc, offset, server);
    if length(s.stack) > 2 && s.stack[2] isa EXPR{CSTParser.ModuleH}
        i += s.stack[2].args[1].fullspan + s.stack[2].args[2].fullspan
        for x in s.stack[3].args 
            i += x.fullspan
            if x == s.stack[4] 
                p1, p2, p3 = i - x.fullspan, i - x.fullspan + length(x.span), i 
                break
            end
        end
    end
    response = JSONRPC.Response(get(r.id), (ind2chr(doc._content, max(1, p1)), ind2chr(doc._content, p2), ind2chr(doc._content, p3)))
    
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/getCurrentBlockOffsetRange")}}, params)
    return TextDocumentPositionParams(params)
end

function remove_workspace_files(root, server)
    for (uri, doc) in server.documents
        fpath = uri2filepath(uri._uri)
        doc._open_in_editor && continue
        if startswith(fpath, fpath)
            for folder in server.workspaceFolders
                if startswith(fpath, folder)
                    continue
                end
                delete!(server.documents, uri)
            end
        end
    end
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWorkspaceFolders")}}, server)
    for wksp in r.params.event.added
        push!(server.workspaceFolders, uri2filepath(wksp.uri))
        load_folder(wksp, server)
    end
    for wksp in r.params.event.removed
        delete!(server.workspaceFolders, uri2filepath(wksp.uri))
        remove_workspace_files(wksp, server)
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWorkspaceFolders")}}, params)
    return didChangeWorkspaceFoldersParams(params)
end

