@testset "_valid_ws_delete" begin
    function test_can_delete_ws(text, deletion_range)
        LanguageServer._valid_ws_delete(CSTParser.parse(text), deletion_range, deletion_range, text)
    end
    @test test_can_delete_ws("x  ", 1:2)
    @test test_can_delete_ws("x  ", 2:3)
    @test test_can_delete_ws("x\n\n", 1:2)
    @test test_can_delete_ws("x\n\n", 2:3)
    @test !test_can_delete_ws("x\n ", 1:2)
    @test !test_can_delete_ws("x \n", 2:3)
end

@testset "_valid_ws_add" begin
    function test_can_add_ws(old_text, insert_text, insert_range)
        LanguageServer._valid_ws_add(CSTParser.parse(old_text), insert_range, insert_range, insert_text, old_text)
    end
    @test test_can_add_ws("x  ", " ", 1)
    @test test_can_add_ws("x  ", " ", 2)
    @test test_can_add_ws("x  ", " ", 3)
    @test test_can_add_ws("x  \n", " ", 4)
    @test test_can_add_ws("x  \n", "\n", 2)
    @test test_can_add_ws("x  \n", "\n", 4)
end

@testset "_noimpact_partial_update" begin
    function test_noimpact_partial_update(old_text, insert_range, insert_text)
        new_text = LanguageServer.edit_string(old_text, insert_range, insert_text)
        cst = CSTParser.parse(old_text, true)
        suc = LanguageServer._noimpact_partial_update(cst, insert_range, insert_text, old_text)
        return suc && CSTParser.isequiv(cst, CSTParser.parse(new_text, true)) && isempty(CSTParser.check_span(cst))
    end
    @testset "add to number" begin
        @test test_noimpact_partial_update("11", 0, "3")
        @test test_noimpact_partial_update("11", 1, "3")
        @test test_noimpact_partial_update("11", 2, "3")
        @test test_noimpact_partial_update("1.1", 0, "3")
        @test test_noimpact_partial_update("1.1", 1, "3")
        @test test_noimpact_partial_update("1.1", 2, "3")
        @test test_noimpact_partial_update("1.1", 3, "3")

        @test !test_noimpact_partial_update("1.1", 3, "33")
    end
    @testset "add to ws" begin
        @test test_noimpact_partial_update("11 ", 2, " ")
        @test test_noimpact_partial_update("11 ", 3, " ")
        @test test_noimpact_partial_update("11 ", 3, "    ")
        @test !test_noimpact_partial_update("11", 2, " ")
    end

    @testset "delete integer" begin
        @test test_noimpact_partial_update("12345 ", 2:3, "")
        @test test_noimpact_partial_update("12345 ", 2:4, "")
    end
    @testset "delete ws" begin
        @test test_noimpact_partial_update("11    ", 2:3, "")
        @test test_noimpact_partial_update("11    ", 2:5, "")
        @test test_noimpact_partial_update("11    ", 3:6, "")
        @test !test_noimpact_partial_update("11    ", 2:6, "")
        @test test_noimpact_partial_update("11\n\n", 2:3, "")
        @test test_noimpact_partial_update("11\n\n", 3:4, "")
        @test !test_noimpact_partial_update("11\n", 2:3, "")
    end

end
