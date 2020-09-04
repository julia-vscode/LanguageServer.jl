@testset "getCurrentBlockRange" begin
    doc = settestdoc("ab")

    res = (LanguageServer.Position(0, 0), LanguageServer.Position(0, 2), LanguageServer.Position(0, 2))
    
    @test LanguageServer.julia_getCurrentBlockRange_request(LanguageServer.VersionedTextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), 0,LanguageServer.Position(0, 0)), server, server.jr_endpoint) == res

    @test LanguageServer.julia_getCurrentBlockRange_request(LanguageServer.VersionedTextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), 0,LanguageServer.Position(0, 1)), server, server.jr_endpoint) == res

    @test LanguageServer.julia_getCurrentBlockRange_request(LanguageServer.VersionedTextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), 0,LanguageServer.Position(0, 2)), server, server.jr_endpoint) == res
end

