using JSON, Sockets, Pkg, SymbolServer

init_request = """
{
    "jsonrpc":"2.0",
    "id":0,
    "method":"initialize",
    "params":{"processId":9902,
              "rootPath":null,
              "rootUri":null,
              "capabilities":{"workspace":{"applyEdit":true,"workspaceEdit":{"documentChanges":true},"didChangeConfiguration":{"dynamicRegistration":false},"didChangeWatchedFiles":{"dynamicRegistration":false},"symbol":{"dynamicRegistration":true},"executeCommand":{"dynamicRegistration":true}},"textDocument":{"synchronization":{"dynamicRegistration":true,"willSave":true,"willSaveWaitUntil":true,"didSave":true},"completion":{"dynamicRegistration":true,"completionItem":{"snippetSupport":true}},"hover":{"dynamicRegistration":true},"signatureHelp":{"dynamicRegistration":true},"references":{"dynamicRegistration":true},"documentHighlight":{"dynamicRegistration":true},"documentSymbol":{"dynamicRegistration":true},"formatting":{"dynamicRegistration":true},"rangeFormatting":{"dynamicRegistration":true},"onTypeFormatting":{"dynamicRegistration":true},"definition":{"dynamicRegistration":true},"codeAction":{"dynamicRegistration":true},"codeLens":{"dynamicRegistration":true},"documentLink":{"dynamicRegistration":true},"rename":{"dynamicRegistration":true}}},
              "trace":"off"}
}
"""

init_response_json = JSON.parse("""
{
    "id": 0,
    "jsonrpc": "2.0",
    "result": {
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
}
""")

if Sys.iswindows()
    global_socket_name = "\\\\.\\pipe\\julia-language-server-testrun"
elseif Sys.isunix()
    global_socket_name = joinpath(tempdir(), "julia-language-server-testrun")
else
    error("Unknown operating system.")
end

@async begin
    server = listen(global_socket_name)
    try
        sock = accept(server)
        try
            ls = LanguageServerInstance(sock, sock, false, dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH), Dict())
            run(ls)
        finally
            close(sock)
        end
    finally
        close(server)
    end
end

sleep(1)

client = connect(global_socket_name)
try
    LanguageServer.write_transport_layer(client, init_request)

    msg = LanguageServer.read_transport_layer(client)

    msg_json = JSON.parse(msg)

    @test_broken init_response_json == msg_json
    @test msg_json["result"]["capabilities"]["typeDefinitionProvider"] == false
    @test msg_json["result"]["capabilities"]["renameProvider"] == true
finally
    close(client)
end
