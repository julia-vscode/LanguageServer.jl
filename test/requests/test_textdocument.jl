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

@testitem "TextDocument lifecycle assertions carry diagnostics context" setup=[TestSetup, SharedServer] begin
    u = uri"untitled:lifecycletest"
    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(u, "julia", 3, "x = 1")), server, nothing)

    # (a) A stale didChange (version lower than stored) must still be fatal,
    # and the message must be self-explanatory without leaking the URI/path.
    err = try
        LanguageServer.textDocument_didChange_notification(LanguageServer.DidChangeTextDocumentParams(LanguageServer.VersionedTextDocumentIdentifier(u, 2), [LanguageServer.TextDocumentContentChangeEvent(missing, missing, "y = 2")]), server, nothing)
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    msg = err.msg
    @test occursin("LS version is 3", msg)
    @test occursin("request version is 2", msg)
    @test occursin("open=true", msg)
    @test occursin("uptime_s=", msg)
    @test occursin("client_restart_count=nothing", msg)
    @test occursin("history=[", msg)
    @test occursin("open v3", msg)
    @test occursin("change v2", msg)
    # Crash messages are transmitted verbatim: no URI or path may leak.
    @test !occursin("lifecycletest", msg)
    @test !occursin(string(u), msg)

    LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(u)), server, nothing)

    # (b) didClose for a document that was never opened must still be fatal,
    # with the enriched message (and the offending close in the history).
    u2 = uri"untitled:neveropened"
    err2 = try
        LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(u2)), server, nothing)
        nothing
    catch e
        e
    end
    @test err2 isa ErrorException
    @test occursin("Received textDocument/didClose for a document that is not open", err2.msg)
    @test occursin("open=false", err2.msg)
    @test occursin("history=[close", err2.msg)
    @test !occursin("neveropened", err2.msg)

    # Distinct documents must get distinct short ids, also on 32-bit builds
    # where `hash` is a UInt32 (taking the high digits of a zero-padded
    # rendering collided everything to "00000000" there).
    @test LanguageServer.document_short_id(u) != LanguageServer.document_short_id(u2)
end

@testitem "julialangRestartCount initialization option" setup=[TestSetup] begin
    import Pkg
    using LanguageServer: LanguageServerInstance

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), nothing, mktempdir())
    server.jr_endpoint = nothing
    @test server._client_restart_count === nothing

    init = LanguageServer.InitializeParams(
        TestSetup.init_request.processId,
        TestSetup.init_request.clientInfo,
        TestSetup.init_request.rootPath,
        TestSetup.init_request.rootUri,
        Dict{String,Any}("julialangRestartCount" => 2),
        TestSetup.init_request.capabilities,
        TestSetup.init_request.trace,
        TestSetup.init_request.workspaceFolders,
        TestSetup.init_request.workDoneToken
    )
    LanguageServer.initialize_request(init, server, nothing)
    @test server._client_restart_count == 2
end
