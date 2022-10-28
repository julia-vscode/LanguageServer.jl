semantic_token_test() = LanguageServer.textDocument_semanticTokens_full_request(LanguageServer.SemanticTokensParams(LanguageServer.TextDocumentIdentifier("testdoc"), missing, missing), server, server.jr_endpoint)

@testset "function calls" begin
    settestdoc("""
    function hello()
        println("hello world")
    end
    """)
    @test semantic_token_test() == SemanticToken(0, 9, 5, SemanticTokenKinds.Function)
end
