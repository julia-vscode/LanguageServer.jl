@testitem "Communication" begin
    import JSON, JSONRPC, Pkg
    using Sockets

    include("test_shared_init_request.jl")

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
            "renameProvider": {
                "prepareProvider": true
            },
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

    global_socket_name = JSONRPC.generate_pipe_name()

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
        @test response["capabilities"]["renameProvider"] == Dict("prepareProvider" => true)
    finally
        close(client)
    end
end
