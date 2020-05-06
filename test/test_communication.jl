init_request = JSON.parse("""
{
    "processId":9902,
    "rootPath":null,
    "rootUri":null,
    "capabilities":{"workspace":{"applyEdit":true,"workspaceEdit":{"documentChanges":true},"didChangeConfiguration":{"dynamicRegistration":false},"didChangeWatchedFiles":{"dynamicRegistration":false},"symbol":{"dynamicRegistration":true},"executeCommand":{"dynamicRegistration":true}},"textDocument":{"synchronization":{"dynamicRegistration":true,"willSave":true,"willSaveWaitUntil":true,"didSave":true},"completion":{"dynamicRegistration":true,"completionItem":{"snippetSupport":true}},"hover":{"dynamicRegistration":true},"signatureHelp":{"dynamicRegistration":true},"references":{"dynamicRegistration":true},"documentHighlight":{"dynamicRegistration":true},"documentSymbol":{"dynamicRegistration":true},"formatting":{"dynamicRegistration":true},"rangeFormatting":{"dynamicRegistration":true},"onTypeFormatting":{"dynamicRegistration":true},"definition":{"dynamicRegistration":true},"codeAction":{"dynamicRegistration":true},"codeLens":{"dynamicRegistration":true},"documentLink":{"dynamicRegistration":true},"rename":{"dynamicRegistration":true}}},
    "trace":"off"
}
""")

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
            ls = LanguageServerInstance(sock, sock, dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
            run(ls)
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
    endpoint = LanguageServer.JSONRPCEndpoints.JSONRPCEndpoint(client, client)
    run(endpoint)

    response = LanguageServer.JSONRPCEndpoints.send_request(endpoint, "initialize", init_request)

    @test_broken init_response == response
    @test response["capabilities"]["typeDefinitionProvider"] == false
    @test response["capabilities"]["renameProvider"] == true
finally
    close(client)
end
