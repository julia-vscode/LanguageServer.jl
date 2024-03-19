@testitem "getCurrentBlockRange" begin
    include("../test_shared_server.jl")

    doc = settestdoc("ab")

    res = (LanguageServer.Position(0, 0), LanguageServer.Position(0, 2), LanguageServer.Position(0, 2))

    @test LanguageServer.julia_getCurrentBlockRange_request(LanguageServer.VersionedTextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), 0, LanguageServer.Position(0, 0)), server, server.jr_endpoint) == res

    @test LanguageServer.julia_getCurrentBlockRange_request(LanguageServer.VersionedTextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), 0, LanguageServer.Position(0, 1)), server, server.jr_endpoint) == res

    @test LanguageServer.julia_getCurrentBlockRange_request(LanguageServer.VersionedTextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), 0, LanguageServer.Position(0, 2)), server, server.jr_endpoint) == res
end
