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

@testitem "inlayHint request with out-of-range position does not crash the server" setup=[TestSetup, SharedServer] begin
    server.inlay_hints = true
    settestdoc("for\nx\ny\nz")

    # A range whose stop position points past the last line of the document
    # (e.g. a sync race between a snippet insertion and the inlayHint request).
    # This must produce a graceful result, not an uncaught exception that
    # unwinds the dispatch loop and kills the server.
    params = LanguageServer.InlayHintParams(
        LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"),
        LanguageServer.Range(LanguageServer.Position(0, 0), LanguageServer.Position(99, 0)),
        missing,
    )
    result = LanguageServer.textDocument_inlayHint_request(params, server, server.jr_endpoint)
    @test result === nothing || result isa Vector{LanguageServer.InlayHint}

    closetestdoc()
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
