@testitem "TextDocument" setup=[TestSetup, SharedServer] begin
    isopen(uri) = haskey(server._open_file_versions, uri)

    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri"untitled:none", "julia", 0, "")), server, server.jr_endpoint)
    @test isopen(uri"untitled:none")
    LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:none")), server, nothing)

    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri"untitled:none", "julia", 0, "")), server, server.jr_endpoint)
    @test isopen(uri"untitled:none")

    LanguageServer.textDocument_didSave_notification(LanguageServer.DidSaveTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:none"), ""), server, server.jr_endpoint)

    LanguageServer.textDocument_didChange_notification(LanguageServer.DidChangeTextDocumentParams(LanguageServer.VersionedTextDocumentIdentifier(uri"untitled:none", 0), [LanguageServer.TextDocumentContentChangeEvent(missing, missing, "ran")]), server, server.jr_endpoint)


    LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:none")), server, server.jr_endpoint)
    @test !isopen(uri"untitled:none")
end

@testitem "Range: an out-of-bounds byte range clamps to EOF instead of crashing" begin
    using JuliaWorkspaces: SourceText

    st = SourceText("abc\ndef\n", "julia")
    n = sizeof(st.content)  # 8
    eof = LanguageServer.get_position_from_offset(st, n)

    # A diagnostic/test-item range can be computed against a newer/older revision
    # than the current content (the analysis result and the document race). An
    # exclusive end past EOF must degrade to the document end, not throw
    # LSPositionToOffsetException and crash the whole request.
    r = LanguageServer.Range(st, (n + 1):(n + 3))
    @test r.stop.line == eof[1]
    @test r.stop.character == eof[2]

    # An in-bounds range is unaffected.
    r2 = LanguageServer.Range(st, 1:4)
    @test r2.start == LanguageServer.Position(0, 0)
    @test r2.stop == LanguageServer.Position(0, 3)
end

@testitem "TextDocument didSave sync mismatch (#1390)" setup=[TestSetup, SharedServer] begin
    u = uri"untitled:synctest"
    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(u, "julia", 0, "x = 1")), server, nothing)

    # A text mismatch at save time for a freshly-opened (version 0) document is
    # spurious and must NOT crash the server (#1390).
    @test (LanguageServer.textDocument_didSave_notification(LanguageServer.DidSaveTextDocumentParams(LanguageServer.TextDocumentIdentifier(u), "different"), server, nothing); true)

    # Bump the version above 0 with a real edit.
    LanguageServer.textDocument_didChange_notification(LanguageServer.DidChangeTextDocumentParams(LanguageServer.VersionedTextDocumentIdentifier(u, 2), [LanguageServer.TextDocumentContentChangeEvent(missing, missing, "y = 2")]), server, nothing)

    # Now a genuine mismatch (open, version > 0) is still reported.
    @test_throws LanguageServer.LSSyncMismatch LanguageServer.textDocument_didSave_notification(LanguageServer.DidSaveTextDocumentParams(LanguageServer.TextDocumentIdentifier(u), "different"), server, nothing)

    # Matching text never crashes.
    @test (LanguageServer.textDocument_didSave_notification(LanguageServer.DidSaveTextDocumentParams(LanguageServer.TextDocumentIdentifier(u), "y = 2"), server, nothing); true)

    LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(u)), server, nothing)
end
