JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWatchedFiles")}}, params) = DidChangeWatchedFilesParams(params)
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")},DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri
        !haskey(server.documents, URI2(uri)) && continue
        if change.type == FileChangeTypes["Created"] || (change.type == FileChangeTypes["Changed"] && !get_open_in_editor(server.documents[URI2(uri)]))
            doc = server.documents[URI2(uri)]
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            content == get_text(doc) && return
            server.documents[URI2(uri)] = Document(uri, content, true, server)
            parse_all(server.documents[URI2(uri)], server)

        elseif change.type == FileChangeTypes["Deleted"] && !get_open_in_editor(server.documents[URI2(uri)])
            delete!(server.documents, URI2(uri))

            publishDiagnosticsParams = PublishDiagnosticsParams(uri, Diagnostic[])
            send_notification(server.jr_endpoint, "textDocument/publishDiagnostics", publishDiagnosticsParams)
        end
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server::LanguageServerInstance)
    request_julia_config(server)
end

function request_julia_config(server)
    response = send_request(server.jr_endpoint, "workspace/configuration", ConfigurationParams([
        (ConfigurationItem(missing, "julia.format.$opt") for opt in fieldnames(DocumentFormat.FormatOptions))...;
        ConfigurationItem(missing, "julia.lint.run");
        (ConfigurationItem(missing, "julia.lint.$opt") for opt in fieldnames(StaticLint.LintOptions))...
        ]))
    
        # TODO Make sure update_julia_config can deal with the response
    update_julia_config(response, server)
end

function update_julia_config(message_dict, server)
    if length(message_dict["result"]) == length(fieldnames(DocumentFormat.FormatOptions)) + 1 + length(fieldnames(StaticLint.LintOptions))
        server.format_options = DocumentFormat.FormatOptions(
            message_dict["result"][1]===nothing ? 0 : message_dict["result"][1],
            message_dict["result"][2]===nothing ? false : message_dict["result"][2],
            message_dict["result"][3]===nothing ? false : message_dict["result"][3],
            message_dict["result"][4]===nothing ? false : message_dict["result"][4],
            message_dict["result"][5]===nothing ? false : message_dict["result"][5],
            message_dict["result"][6]===nothing ? false : message_dict["result"][6],
            message_dict["result"][7]===nothing ? false : message_dict["result"][7],
            message_dict["result"][8]===nothing ? false : message_dict["result"][8],
            message_dict["result"][9]===nothing ? false : message_dict["result"][9],
            message_dict["result"][10]===nothing ? false : message_dict["result"][10],
            message_dict["result"][11]===nothing ? false : message_dict["result"][11])
        
        N = length(fieldnames(DocumentFormat.FormatOptions)) + 1
        x = message_dict["result"][N]
        new_lint_opts = StaticLint.LintOptions(
            message_dict["result"][N + 1]===nothing ? false : message_dict["result"][N + 1],
            message_dict["result"][N + 2]===nothing ? false : message_dict["result"][N + 2],
            message_dict["result"][N + 3]===nothing ? false : message_dict["result"][N + 3],
            message_dict["result"][N + 4]===nothing ? false : message_dict["result"][N + 4],
            message_dict["result"][N + 5]===nothing ? false : message_dict["result"][N + 5],
            message_dict["result"][N + 6]===nothing ? false : message_dict["result"][N + 6],
            message_dict["result"][N + 7]===nothing ? false : message_dict["result"][N + 7],
            message_dict["result"][N + 8]===nothing ? false : message_dict["result"][N + 8],
            message_dict["result"][N + 9]===nothing ? false : message_dict["result"][N + 9],
        )
        
        new_run_lint_value = x===nothing ? false : true
        if new_run_lint_value != server.runlinter || any(getfield(new_lint_opts, n) != getfield(server.lint_options, n) for n in fieldnames(StaticLint.LintOptions))
            server.lint_options = new_lint_opts
            server.runlinter = new_run_lint_value
            for doc in values(server.documents)
                StaticLint.check_all(getcst(doc), server.lint_options, server)
                empty!(doc.diagnostics)
                mark_errors(doc, doc.diagnostics)
                publish_diagnostics(doc, server)
            end
        end
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWorkspaceFolders")}}, params) = DidChangeWorkspaceFoldersParams(params)
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


JSONRPC.parse_params(::Type{Val{Symbol("workspace/symbol")}}, params) = WorkspaceSymbolParams(params) 
function process(r::JSONRPC.Request{Val{Symbol("workspace/symbol")},WorkspaceSymbolParams}, server) 
    syms = SymbolInformation[]
    for (uri,doc) in server.documents
        bs = collect_toplevel_bindings_w_loc(getcst(doc), query = r.params.query)
        for x in bs
            p, b = x[1], x[2]
            push!(syms, SymbolInformation(valof(b.name), 1, false, Location(doc._uri, Range(doc, p)), nothing))
        end
    end

    return syms
end