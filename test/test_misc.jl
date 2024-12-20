@testitem "get_file_loc" begin
    import CSTParser

    str = "(x+y for x in X for y in Y if begin if true end end)"
    cst = CSTParser.parse(str)
    @test LanguageServer.get_file_loc(cst[2][5][1][1]) == (nothing, 20)
end
