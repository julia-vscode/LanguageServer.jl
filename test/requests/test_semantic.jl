
@testitem "simple token" begin
    include("../test_shared_server.jl")

    let _LS = LanguageServer,
        _encoding = _LS.semantic_token_encoding

        doc = settestdoc("""a=123""")
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
        doc = settestdoc("""const C = CSTParser""")
        @test Int64.(token_full_test().data) == Int64.(_LS.SemanticTokens(
            UInt32[0, 0,
                5, # «const » TODO WIP
                _encoding(_LS.SemanticTokenKinds.Keyword), 0,
                0, 6,
                1, # «C»
                _encoding(_LS.SemanticTokenKinds.Variable), 0,
                0, 8,
                1, # «=»
                _encoding(_LS.SemanticTokenKinds.Operator), 0,
                0, 10,
                9, # «CSTParser»
                _encoding(_LS.SemanticTokenKinds.Variable), 0,
            ]).data)
    end
end
