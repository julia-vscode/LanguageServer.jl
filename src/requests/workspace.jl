JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWatchedFiles")}}, params) = DidChangeWatchedFilesParams(params)
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")},DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri

        startswith(uri, "file:") || continue

        if change.type == FileChangeTypes.Created || change.type == FileChangeTypes.Changed
            if hasdocument(server, URI2(uri))
                doc = getdocument(server, URI2(uri))

                # Currently managed by the client, we don't do anything
                if get_open_in_editor(doc)
                    continue
                else
                    filepath = uri2filepath(uri)
                    content = try
                        s = read(filepath, String)
                        if !isvalid(s)
                            deletedocument!(server, URI2(uri))
                            continue
                        end
                        s
                    catch err
                        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
                        deletedocument!(server, URI2(uri))
                        continue
                    end
        
                    set_text!(doc, content)
                    set_is_workspace_file(doc, true)
                    parse_all(doc, server)    
                end
            else
                filepath = uri2filepath(uri)
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
        elseif change.type == FileChangeTypes.Deleted
            if hasdocument(server, URI2(uri))
                doc = getdocument(server, URI2(uri))

                # We only handle if currently not managed by client
                if !get_open_in_editor(doc)
                    deletedocument!(server, URI2(uri))

                    publishDiagnosticsParams = PublishDiagnosticsParams(uri, missing, Diagnostic[])
                    JSONRPCEndpoints.send_notification(server.jr_endpoint, "textDocument/publishDiagnostics", publishDiagnosticsParams)
                else
                    # TODO replace with accessor function once the other PR
                    # that introduces the accessor is merged
                    doc._workspace_file = false
                end
            end
        else
            error("Unknown change type.")
        end
    end
end

JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server::LanguageServerInstance)
    request_julia_config(server)
end

function request_julia_config(server::LanguageServerInstance)
    server.clientCapabilities.workspace.configuration === false && return # Or !== true?
    
    response = JSONRPCEndpoints.send_request(server.jr_endpoint, "workspace/configuration", ConfigurationParams([
        ConfigurationItem(missing, "julia.format.indent"), # FormatOptions
        ConfigurationItem(missing, "julia.format.indents"),
        ConfigurationItem(missing, "julia.format.ops"),
        ConfigurationItem(missing, "julia.format.tuples"),
        ConfigurationItem(missing, "julia.format.curly"), 
        ConfigurationItem(missing, "julia.format.call"),
        ConfigurationItem(missing, "julia.format.iterOps"),
        ConfigurationItem(missing, "julia.format.comments"),
        ConfigurationItem(missing, "julia.format.docs"),
        ConfigurationItem(missing, "julia.format.lineends"),
        ConfigurationItem(missing, "julia.format.kw"),
        ConfigurationItem(missing, "julia.lint.call"), # LintOptions
        ConfigurationItem(missing, "julia.lint.iter"),
        ConfigurationItem(missing, "julia.lint.nothingcomp"),
        ConfigurationItem(missing, "julia.lint.constif"),
        ConfigurationItem(missing, "julia.lint.lazyif"),
        ConfigurationItem(missing, "julia.lint.datadecl"),
        ConfigurationItem(missing, "julia.lint.typeparam"),
        ConfigurationItem(missing, "julia.lint.modname"),
        ConfigurationItem(missing, "julia.lint.pirates"),
        ConfigurationItem(missing, "julia.lint.useoffuncargs"),
        ConfigurationItem(missing, "julia.lint.run"),
        ConfigurationItem(missing, "julia.lint.missingrefs")
        ]))

    server.format_options = DocumentFormat.FormatOptions(response[1:11]...)
    server.runlinter = something(response[22], true)
    server.lint_missingrefs = Symbol(something(response[23], :all))

    new_SL_opts = StaticLint.LintOptions(response[12:21]...)
    # TODO: implement == for StaticLint.LintOptions
    rerun_lint = any(getproperty(server.lint_options, opt) != getproperty(new_SL_opts, opt) for opt in fieldnames(StaticLint.LintOptions))
    server.lint_options = new_SL_opts

    if rerun_lint
        for doc in getdocuments_value(server)
            lint!(doc, server)
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
    for doc in getdocuments_value(server)
        bs = collect_toplevel_bindings_w_loc(getcst(doc), query = r.params.query)
        for x in bs
            p, b = x[1], x[2]
            push!(syms, SymbolInformation(valof(b.name), 1, false, Location(doc._uri, Range(doc, p)), missing))
        end
    end

    return syms
end
