init_request = LanguageServer.InitializeParams(
    9902,
    missing,
    nothing,
    nothing,
    missing,
    LanguageServer.ClientCapabilities(
        LanguageServer.WorkspaceClientCapabilities(
            true,
            LanguageServer.WorkspaceEditClientCapabilities(true, missing, missing),
            LanguageServer.DidChangeConfigurationClientCapabilities(false),
            LanguageServer.DidChangeWatchedFilesClientCapabilities(false, ),
            LanguageServer.WorkspaceSymbolClientCapabilities(true, missing),
            LanguageServer.ExecuteCommandClientCapabilities(true),
            missing,
            missing
        ),
        LanguageServer.TextDocumentClientCapabilities(
            LanguageServer.TextDocumentSyncClientCapabilities(true, true, true, true),
            LanguageServer.CompletionClientCapabilities(true, LanguageServer.CompletionItemClientCapabilities(true, missing, missing, missing, missing, missing), missing, missing),
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
            LanguageServer.RenameClientCapabilities(true, missing),
            missing, # PublishDiagnosticsClientCapabilities(),
            missing, # FoldingRangeClientCapabilities(),
            missing, # SelectionRangeClientCapabilities()
        ),
        missing,
        missing
    ),
    "off",
    missing,
    missing
)

init_response = JSON.parse("""
{
    "capabilities": {
        "textDocumentSync": 2,
        "hoverProvider": true,
        "completionProvider": {
            "resolveProvider": false,
            "triggerCharacters": [
                "."
            ]
        },
        "signatureHelpProvider": {
            "triggerCharacters": [
                "("
            ]
        },
        "definitionProvider": true,
        "typeDefinitionProvider": false,
        "implementationProvider": false,
        "referencesProvider": true,
        "documentHighlightProvider": false,
        "documentSymbolProvider": true,
        "workspaceSymbolProvider": true,
        "codeActionProvider": true,
        "documentFormattingProvider": true,
        "documentRangeFormattingProvider": false,
        "renameProvider": true,
        "documentLinkProvider": {
            "resolveProvider": false
        },
        "colorProvider": false,
        "executeCommandProvider": {
            "commands": []
        },
        "workspace": {
            "workspaceFolders": {
                "supported": true,
                "changeNotifications": true
            }
        },
        "experimental": null
    }
}
""")

if Sys.iswindows()
    global_socket_name = "\\\\.\\pipe\\julia-language-server-testrun"
elseif Sys.isunix()
    global_socket_name = joinpath(tempdir(), "julia-language-server-testrun")
else
    error("Unknown operating system.")
end

@async try
    server = listen(global_socket_name)
    try
        sock = accept(server)
        try
            runserver(sock, sock, Pkg.Types.Context().env.project_file, first(DEPOT_PATH))
        finally
            close(sock)
        end
    finally
        close(server)
    end
catch err
    Base.display_error(stderr, err, catch_backtrace())
    rethrow()
end

sleep(1)

client = connect(global_socket_name)
try
    endpoint = JSONRPC.JSONRPCEndpoint(client, client)
    run(endpoint)

    response = JSONRPC.send_request(endpoint, "initialize", init_request)

    @test_broken init_response == response
    @test response["capabilities"]["typeDefinitionProvider"] == false
    @test response["capabilities"]["renameProvider"] == true
finally
    close(client)
end
