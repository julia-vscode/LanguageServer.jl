@testitem "request on unknown document does not crash the server (#1393)" setup=[TestSetup, SharedServer] begin
    using LanguageServer.URIs2

    # A URI the server never received a didOpen for (e.g. a notebook cell).
    unknown_uri = URIs2.URI("vscode-notebook-cell", nothing, "/c:/foo/bar.ipynb", nothing, "X23sZmlsZQ==")

    # Document accessors raise MissingDocumentError for unknown URIs …
    @test_throws LanguageServer.MissingDocumentError LanguageServer.jw_source_text(server, unknown_uri)

    # … and the request wrapper turns that into a graceful JSON-RPC error
    # instead of letting the server crash.
    params = LanguageServer.CodeActionParams(
        LanguageServer.TextDocumentIdentifier(unknown_uri),
        LanguageServer.Range(LanguageServer.Position(0, 0), LanguageServer.Position(0, 0)),
        LanguageServer.CodeActionContext([], missing),
    )
    wrapped = LanguageServer.request_wrapper(LanguageServer.textDocument_codeAction_request, server)
    result = wrapped(server.jr_endpoint, params, missing)
    @test result isa LanguageServer.JSONRPC.JSONRPCError
end

@testitem "editor pid monitoring (#1379)" setup=[TestSetup, SharedServer] begin
    # No editor pid known → no monitor task.
    server.editor_pid = nothing
    @test LanguageServer.poll_editor_pid(server) === nothing

    # Once a pid is set, a monitor task is spawned. Pre-set shutdown_requested so
    # the loop exits on its first check (no sleep, no exit path).
    server.editor_pid = Int(Base.Libc.getpid())
    server.shutdown_requested = true
    t = LanguageServer.poll_editor_pid(server)
    @test t isa Task
end
