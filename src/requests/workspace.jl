function workspace_didChangeWatchedFiles_notification(params::DidChangeWatchedFilesParams, server::LanguageServerInstance, conn)
    for change in params.changes
        uri = change.uri

        uri.scheme=="file" || continue

        if change.type == FileChangeTypes.Created || change.type == FileChangeTypes.Changed
            if change.type == FileChangeTypes.Created
                server.workspace = add_file(server.workspace, uri)
            elseif change.type == FileChangeTypes.Changed
                server.workspace = update_file(server.workspace, uri)
            end

            if hasdocument(server, uri)
                doc = getdocument(server, uri)

                # Currently managed by the client, we don't do anything
                if get_open_in_editor(doc)
                    continue
                else
                    filepath = uri2filepath(uri)
                    content = try
                        s = read(filepath, String)
                        if !our_isvalid(s)
                            deletedocument!(server, uri)
                            continue
                        end
                        s
                    catch err
                        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
                        deletedocument!(server, uri)
                        continue
                    end

                    set_text_document!(doc, TextDocument(uri, content, 0))
                    set_is_workspace_file(doc, true)
                    parse_all(doc, server)
                end
            else
                filepath = uri2filepath(uri)
                content = try
                    s = read(filepath, String)
                    our_isvalid(s) || continue
                    s
                catch err
                    isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
                    continue
                end

                doc = Document(TextDocument(uri, content, 0), true, server)
                setdocument!(server, uri, doc)
                parse_all(doc, server)
            end
        elseif change.type == FileChangeTypes.Deleted
            server.workspace = delete_file(server.workspace, uri)

            if hasdocument(server, uri)
                doc = getdocument(server, uri)

                # We only handle if currently not managed by client
                if !get_open_in_editor(doc)
                    deletedocument!(server, uri)

                    publishDiagnosticsParams = PublishDiagnosticsParams(uri, missing, Diagnostic[])
                    JSONRPC.send(conn, textDocument_publishDiagnostics_notification_type, publishDiagnosticsParams)
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

function workspace_didChangeConfiguration_notification(params::DidChangeConfigurationParams, server::LanguageServerInstance, conn)
    if !server.clientcapability_workspace_didChangeConfiguration
        @debug "Client sent a `workspace/didChangeConfiguration` request despite claiming no support for it. " *
               "The request will be handled regardless, but this behavior can be reported to the client."
    end
    request_julia_config(server, conn)
end

@static if VERSION < v"1.1"
    isnothing(::Any) = false
    isnothing(::Nothing) = true
end

const LINT_DIABLED_DIRS = ["test", "docs"]

function request_julia_config(server::LanguageServerInstance, conn)
    (ismissing(server.clientCapabilities.workspace) || server.clientCapabilities.workspace.configuration !== true) && return

    response = JSONRPC.send(conn, workspace_configuration_request_type, ConfigurationParams([
        ConfigurationItem(missing, "julia.lint.call"), # LintOptions
        ConfigurationItem(missing, "julia.lint.iter"),
        ConfigurationItem(missing, "julia.lint.nothingcomp"),
        ConfigurationItem(missing, "julia.lint.constif"),
        ConfigurationItem(missing, "julia.lint.lazy"),
        ConfigurationItem(missing, "julia.lint.datadecl"),
        ConfigurationItem(missing, "julia.lint.typeparam"),
        ConfigurationItem(missing, "julia.lint.modname"),
        ConfigurationItem(missing, "julia.lint.pirates"),
        ConfigurationItem(missing, "julia.lint.useoffuncargs"),
        ConfigurationItem(missing, "julia.lint.run"),
        ConfigurationItem(missing, "julia.lint.missingrefs"),
        ConfigurationItem(missing, "julia.lint.disabledDirs"),
        ConfigurationItem(missing, "julia.completionmode"),
        ConfigurationItem(missing, "julia.inlayHints"),
    ]))

    new_runlinter = something(response[11], true)
    new_SL_opts = StaticLint.LintOptions(response[1:10]...)

    new_lint_missingrefs = Symbol(something(response[12], :all))
    new_lint_disableddirs = something(response[13], LINT_DIABLED_DIRS)
    new_completion_mode = Symbol(something(response[14], :import))
    inlayHints = Symbol(something(response[15], :literals))

    rerun_lint = begin
        any(getproperty(server.lint_options, opt) != getproperty(new_SL_opts, opt) for opt in fieldnames(StaticLint.LintOptions)) ||
        server.runlinter != new_runlinter ||
        server.lint_missingrefs != new_lint_missingrefs ||
        server.lint_disableddirs != new_lint_disableddirs
    end

    server.lint_options = new_SL_opts
    server.runlinter = new_runlinter
    server.lint_missingrefs = new_lint_missingrefs
    server.lint_disableddirs = new_lint_disableddirs
    server.completion_mode = new_completion_mode
    server.inlay_hint_mode = inlayHints

    if rerun_lint
        relintserver(server)
    end
end

function workspace_didChangeWorkspaceFolders_notification(params::DidChangeWorkspaceFoldersParams, server::LanguageServerInstance, conn)
    for wksp in params.event.added
        push!(server.workspaceFolders, uri2filepath(wksp.uri))
        load_folder(wksp, server)
        server.workspace = add_workspace_folder(server.workspace, wksp.uri)
    end
    for wksp in params.event.removed
        delete!(server.workspaceFolders, uri2filepath(wksp.uri))
        remove_workspace_files(wksp, server)
        server.workspace = remove_workspace_folder(server.workspace, wksp.uri)
    end
end

function workspace_symbol_request(params::WorkspaceSymbolParams, server::LanguageServerInstance, conn)
    syms = SymbolInformation[]
    for doc in getdocuments_value(server)
        bs = collect_toplevel_bindings_w_loc(getcst(doc), query=params.query)
        for x in bs
            p, b = x[1], x[2]
            push!(syms, SymbolInformation(valof(b.name), 1, false, Location(get_uri(doc), Range(doc, p)), missing))
        end
    end

    return syms
end
