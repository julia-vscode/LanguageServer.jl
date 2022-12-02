
@testitem "simple token" begin
    include("../test_shared_server.jl")

    doc = settestdoc("""
a=1
    """)
    let _LS = LanguageServer
        @test Int64.(token_full_test().data) == Int64.(_LS.SemanticTokens(UInt32[0, 0, 9, 5, _LS.semantic_token_encoding(_LS.SemanticTokenKinds.Variable)]).data)
    end
end
