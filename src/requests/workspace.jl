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
            JSONRPCEndpoints.send_notification(server.jr_endpoint, "textDocument/publishDiagnostics", publishDiagnosticsParams)
        end
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server::LanguageServerInstance)
    request_julia_config(server)
end

function request_julia_config(server)
    response = JSONRPCEndpoints.send_request(server.jr_endpoint, "workspace/configuration", ConfigurationParams([
        (ConfigurationItem(missing, "julia.format.$opt") for opt in fieldnames(DocumentFormat.FormatOptions))...;
        ConfigurationItem(missing, "julia.lint.run");
        (ConfigurationItem(missing, "julia.lint.$opt") for opt in fieldnames(StaticLint.LintOptions))...
        ]))
    
    # TODO Make sure update_julia_config can deal with the response
    if length(response) == length(fieldnames(DocumentFormat.FormatOptions)) + 1 + length(fieldnames(StaticLint.LintOptions))
        server.format_options = DocumentFormat.FormatOptions(
            response[1]===nothing ? 0 : response[1],
            response[2]===nothing ? false : response[2],
            response[3]===nothing ? false : response[3],
            response[4]===nothing ? false : response[4],
            response[5]===nothing ? false : response[5],
            response[6]===nothing ? false : response[6],
            response[7]===nothing ? false : response[7],
            response[8]===nothing ? false : response[8],
            response[9]===nothing ? false : response[9],
            response[10]===nothing ? false : response[10],
            response[11]===nothing ? false : response[11])
        
        N = length(fieldnames(DocumentFormat.FormatOptions)) + 1
        x = response[N]
        new_lint_opts = StaticLint.LintOptions(
            response[N + 1]===nothing ? false : response[N + 1],
            response[N + 2]===nothing ? false : response[N + 2],
            response[N + 3]===nothing ? false : response[N + 3],
            response[N + 4]===nothing ? false : response[N + 4],
            response[N + 5]===nothing ? false : response[N + 5],
            response[N + 6]===nothing ? false : response[N + 6],
            response[N + 7]===nothing ? false : response[N + 7],
            response[N + 8]===nothing ? false : response[N + 8],
            response[N + 9]===nothing ? false : response[N + 9],
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