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

@testitem "documentHighlight past EOF reports document sync context" setup=[TestSetup, SharedServer] begin
    settestdoc("x = 1")

    # A position on a line the server's text does not have. This still crashes
    # the server (that is deliberate: it is a sync bug we want reported), but
    # the crash message must carry enough state to explain the mismatch.
    params = LanguageServer.DocumentHighlightParams(
        LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"),
        LanguageServer.Position(1, 0),
        missing,
        missing,
    )
    wrapped = LanguageServer.request_wrapper(LanguageServer.textDocument_documentHighlight_request, server)
    err = try
        wrapped(server.jr_endpoint, params, missing)
        nothing
    catch e
        e
    end
    @test err isa LanguageServer.LSOffsetError
    msg = sprint(showerror, err)
    @test occursin("index_at crashed", msg)
    @test occursin("handler=textDocument_documentHighlight_request", msg)
    @test occursin("scheme=untitled", msg)
    @test occursin("open=true", msg)
    @test occursin("version=0", msg)
    @test occursin("line_count=1", msg)
    @test occursin("from_disc=false", msg)

    closetestdoc()
end

@testitem "LSOffsetError reports when the workspace serves the disc copy" setup=[TestSetup, SharedServer] begin
    u = uri"untitled:testdoc"
    settestdoc("x = 1\ny = 2")

    # Pretend the document also exists on disc with fewer lines, then close it:
    # didClose reverts the workspace to the disc copy, so a request at a line
    # that only the editor buffer had must report `serving_disc_copy=true`.
    server._files_from_disc[u] = LanguageServer.JuliaWorkspaces.TextFile(u, LanguageServer.JuliaWorkspaces.SourceText("x = 1", "julia"))
    closetestdoc()
    @test LanguageServer.jw_text(server, u) == "x = 1"

    params = LanguageServer.DocumentHighlightParams(
        LanguageServer.TextDocumentIdentifier(u),
        LanguageServer.Position(1, 0),
        missing,
        missing,
    )
    wrapped = LanguageServer.request_wrapper(LanguageServer.textDocument_documentHighlight_request, server)
    err = try
        wrapped(server.jr_endpoint, params, missing)
        nothing
    catch e
        e
    end
    @test err isa LanguageServer.LSOffsetError
    msg = sprint(showerror, err)
    @test occursin("open=false", msg)
    @test occursin("from_disc=true", msg)
    @test occursin("serving_disc_copy=true", msg)

    delete!(server._files_from_disc, u)
    LanguageServer.JuliaWorkspaces.remove_file!(server.workspace, u)
end

@testitem "document_sync_context handles unknown and missing URIs" setup=[TestSetup, SharedServer] begin
    using LanguageServer.URIs2

    unknown_uri = URIs2.URI("vscode-notebook-cell", nothing, "/c:/foo/bar.ipynb", nothing, "X23sZmlsZQ==")
    ctx = LanguageServer.document_sync_context(server, unknown_uri)
    @test occursin("scheme=vscode-notebook-cell", ctx)
    @test occursin("open=false", ctx)
    @test occursin("in_workspace=false", ctx)
    @test !occursin("line_count", ctx)

    @test LanguageServer.document_sync_context(server, nothing) == "uri=<unavailable>"
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
