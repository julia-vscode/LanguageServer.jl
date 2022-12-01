
@testitem "simple token" begin
    include("../test_shared_server.jl")

    doc = settestdoc("""
a=1
    """)
    let _LS = LanguageServer
        @test token_full_test() == _LS.SemanticTokens(UInt32[0, 0, 9, 5, _LS.semantic_token_encoding(_LS.SemanticTokenKinds.Variable)])
    end
end
