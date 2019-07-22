function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWatchedFiles")}}, params)
    return DidChangeWatchedFilesParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")},DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri
        !haskey(server.documents, URI2(uri)) && continue
        if change._type == FileChangeType_Created || (change._type == FileChangeType_Changed && !get_open_in_editor(server.documents[URI2(uri)]))
            doc = server.documents[URI2(uri)]
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            content == doc._content && return
            server.documents[URI2(uri)] = Document(uri, content, true, server)
            parse_all(server.documents[URI2(uri)], server)

        elseif change._type == FileChangeType_Deleted && !get_open_in_editor(server.documents[URI2(uri)])
            delete!(server.documents, URI2(uri))

            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(uri, Diagnostic[]))
            send(response, server)
        end
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params)
    return params
end


function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server::LanguageServerInstance)
    if r.params["settings"] isa Dict && haskey(r.params["settings"], "julia")
        jsettings = r.params["settings"]["julia"]
        if haskey(jsettings, "runLinter") && jsettings["runLinter"] != server.runlinter
            server.runlinter = !server.runlinter
            if server.runlinter
                if !server.isrunning
                    for doc in values(server.documents)
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
                        append!(doc.diagnostics, L.diagnostics)
                        publish_diagnostics(doc, server)
                    end
                end
            end
        end
        if haskey(jsettings, "format")
            for (k,v) in jsettings["format"]
                setproperty!(server.format_options, Symbol(k), v)
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
        bs = collect_toplevel_bindings_w_loc(getcst(doc), query = r.params.query)
        for x in bs
            p, b = x[1], x[2]
            push!(syms, SymbolInformation(b.name, 1, false, Location(doc._uri, Range(doc, p)), nothing))
        end
    end

    response = JSONRPC.Response(r.id, syms) 
    send(response, server) 
end