@testmodule TestSetup begin
    import JSONRPC, LanguageServer

    # No-op for Nothing endpoints (used when no client is connected in tests).
    JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

    # Use the live test process as the "editor" pid: since #1379 starts editor
    # process monitoring during initialize, a dead/fake pid would make the
    # monitor task exit(1) the test worker after its poll interval.
    const init_request = LanguageServer.InitializeParams(
        Int(Base.Libc.getpid()),
        missing,
        nothing,
        nothing,
        missing,
        LanguageServer.ClientCapabilities(
            LanguageServer.WorkspaceClientCapabilities(
                true,
                LanguageServer.WorkspaceEditClientCapabilities(true, missing, missing),
                LanguageServer.DidChangeConfigurationClientCapabilities(false),
                LanguageServer.DidChangeWatchedFilesClientCapabilities(false, false),
                LanguageServer.WorkspaceSymbolClientCapabilities(true, missing),
                LanguageServer.ExecuteCommandClientCapabilities(true),
                missing,
                missing,
                missing
            ),
            LanguageServer.TextDocumentClientCapabilities(
                LanguageServer.TextDocumentSyncClientCapabilities(true, true, true, true),
                LanguageServer.CompletionClientCapabilities(true, LanguageServer.CompletionItemClientCapabilities(true, missing, missing, missing, missing, missing, missing), missing, missing),
                LanguageServer.HoverClientCapabilities(true, missing),
                LanguageServer.SignatureHelpClientCapabilities(true, missing, missing),
                LanguageServer.DeclarationClientCapabilities(false, missing),
                missing, # DefinitionClientCapabilities(),
                missing, # TypeDefinitionClientCapabilities(),
                missing, # ImplementationClientCapabilities(),
                missing, # ReferenceClientCapabilities(),
                LanguageServer.DocumentHighlightClientCapabilities(true),
                LanguageServer.DocumentSymbolClientCapabilities(true, missing, missing),
                LanguageServer.CodeActionClientCapabilities(true, missing, missing),
                LanguageServer.CodeLensClientCapabilities(true),
                missing, # DocumentLinkClientCapabilities(),
                missing, # DocumentColorClientCapabilities(),
                LanguageServer.DocumentFormattingClientCapabilities(true),
                missing, # DocumentRangeFormattingClientCapabilities(),
                missing, # DocumentOnTypeFormattingClientCapabilities(),
                LanguageServer.RenameClientCapabilities(true, true),
                missing, # PublishDiagnosticsClientCapabilities(),
                missing, # FoldingRangeClientCapabilities(),
                missing, # SelectionRangeClientCapabilities()
                missing, # DiagnosticClientCapabilities()
            ),
            missing,
            missing
        ),
        "off",
        missing,
        missing
    )
end

@testsnippet SharedServer begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance

    function settestdoc(text)
        # Close previous test doc if open
        if haskey(server._open_file_versions, uri"untitled:testdoc")
            LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc")), server, nothing)
        end
        LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri"untitled:testdoc", "julia", 0, text)), server, nothing)
    end

    function closetestdoc()
        LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc")), server, nothing)
    end

    completion_test(line, char) = LanguageServer.textDocument_completion_request(LanguageServer.CompletionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing), server, server.jr_endpoint)
    action_request_test(line0, char0, line1=line0, char1=char0; diags=[]) = LanguageServer.textDocument_codeAction_request(LanguageServer.CodeActionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Range(LanguageServer.Position(line0, char0), LanguageServer.Position(line1, char1)), LanguageServer.CodeActionContext(diags, missing)), server, server.jr_endpoint)
    sig_test(line, char) = LanguageServer.textDocument_signatureHelp_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)
    def_test(line, char) = LanguageServer.textDocument_definition_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)
    ref_test(line, char) = LanguageServer.textDocument_references_request(LanguageServer.ReferenceParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing, missing, LanguageServer.ReferenceContext(true)), server, server.jr_endpoint)
    rename_test(line, char) = LanguageServer.textDocument_rename_request(LanguageServer.RenameParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing, "newname"), server, server.jr_endpoint)
    hover_test(line, char) = LanguageServer.textDocument_hover_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)
    range_formatting_test(line0, char0, line1, char1) = LanguageServer.textDocument_range_formatting_request(LanguageServer.DocumentRangeFormattingParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Range(LanguageServer.Position(line0, char0), LanguageServer.Position(line1, char1)), LanguageServer.FormattingOptions(4, true, missing, missing, missing)), server, server.jr_endpoint)

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), nothing, first(Base.DEPOT_PATH))
    server.jr_endpoint = nothing
    LanguageServer.initialize_request(TestSetup.init_request, server, nothing)
    LanguageServer.initialized_notification(LanguageServer.InitializedParams(), server, nothing)
end
