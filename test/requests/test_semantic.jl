
@testitem "simple token" begin
    include("../test_shared_server.jl")

    doc = settestdoc("""
a=123
    """)
    let _LS = LanguageServer,
        _encoding=_LS.semantic_token_encoding
        @test Int64.(token_full_test().data) == Int64.(_LS.SemanticTokens(
                                                                          UInt32[0, 0, # first line, first column
                                                                                 1, # «a»
                                                                                 _encoding(_LS.SemanticTokenKinds.Variable), 0,
                                                                                 0, 1,
                                                                                 1, # «=»
                                                                                 _encoding(_LS.SemanticTokenKinds.Operator), 0,
                                                                                 0, 2,
                                                                                 3, # «123»
                                                                                 _encoding(_LS.SemanticTokenKinds.Number), 0,
                                                                                ]).data)
    end
end
