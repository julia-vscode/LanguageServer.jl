function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWatchedFiles")}}, params)
    return DidChangeWatchedFilesParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")},DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri
        !haskey(server.documents, URI2(uri)) && continue
        if change._type == FileChangeType_Created || (change._type == FileChangeType_Changed && !get_open_in_editor(server.documents[URI2(uri)]))
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            server.documents[URI2(uri)] = Document(uri, content, true, server)
            parse_all(server.documents[URI2(uri)], server)

        elseif change._type == FileChangeType_Deleted && !get_open_in_editor(server.documents[URI2(uri)])
            delete!(server.documents, URI2(uri))

            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), PublishDiagnosticsParams(uri, Diagnostic[]))
            send(response, server)
        end
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params)
    return Any(params)
end


function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server)
    if haskey(r.params["settings"], "julia")
        jsettings = r.params["settings"]["julia"]
        if haskey(jsettings, "runlinter") && jsettings["runlinter"] != server.runlinter
            server.runlinter = !server.runlinter
            if server.runlinter
                if !server.isrunning
                    for doc in values(server.documents)
                        # doc.diagnostics = lint(doc, server).diagnostics
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
                        # L = lint(doc, server)
                        append!(doc.diagnostics, L.diagnostics)
                        publish_diagnostics(doc, server)
                    end
                end
            end

        end
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWorkspaceFolders")}}, params)
    return didChangeWorkspaceFoldersParams(params)
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


function JSONRPC.parse_params(::Type{Val{Symbol("workspace/symbol")}}, params)
    return WorkspaceSymbolParams(params) 
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/symbol")},WorkspaceSymbolParams}, server) 
    syms = SymbolInformation[]
    for (uri,doc) in server.documents
        for (name, bs) in doc.code.state.bindings
            if ismatch(Regex(r.params.query, "i"), name) 
                for b in bs
                    if b.index == doc.code.index && b.val isa CSTParser.AbstractEXPR
                        push!(syms, SymbolInformation(name, 1, Location(doc._uri, Range(doc, b.loc.offset + b.val.span))))
                    end
                end
            end
        end
    end

    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end