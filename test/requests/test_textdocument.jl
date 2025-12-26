@testitem "TextDocument" begin
    include("../test_shared_server.jl")

    empty!(server._documents)

    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri"untitled:none", "julia", 0, "")), server, server.jr_endpoint)
    @test LanguageServer.hasdocument(server, uri"untitled:none")
    LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:none")), server, nothing)

    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri"untitled:none", "julia", 0, "")), server, server.jr_endpoint)
    @test LanguageServer.hasdocument(server, uri"untitled:none")

    LanguageServer.textDocument_didSave_notification(LanguageServer.DidSaveTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:none"), ""), server, server.jr_endpoint)

    LanguageServer.textDocument_didChange_notification(LanguageServer.DidChangeTextDocumentParams(LanguageServer.VersionedTextDocumentIdentifier(uri"untitled:none", 0), [LanguageServer.TextDocumentContentChangeEvent(missing, missing, "ran")]), server, server.jr_endpoint)


    LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:none")), server, server.jr_endpoint)
    @test !LanguageServer.hasdocument(server, uri"untitled:none")
end
