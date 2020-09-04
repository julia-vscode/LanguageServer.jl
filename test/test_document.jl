s1 = """
123456
abcde
ABCDEFG
"""
d1 = Document("untitled", s1, false)
@test get_text(d1) == s1
@test get_offset(d1, 0, 4) == 4
@test get_offset(d1, 1, 2) == 9
@test get_line_offsets(d1) == [0, 7, 13, 21]
@test get_position_at(d1, 1) == (0, 1)
@test get_position_at(d1, 8) == (1, 1)
@test get_position_at(d1, 15) == (2, 2)
@test get_open_in_editor(d1) == false
set_open_in_editor(d1, true)
@test get_open_in_editor(d1) == true
set_open_in_editor(d1, false)
@test get_open_in_editor(d1) == false
@test is_workspace_file(d1) == false


s2 = """
12μ456
abηde
ABCDEFG"""
d2 = Document("untitled", s2, true)
@test get_offset(d2, 0, 4) == 5
@test get_offset(d2, 1, 2) == 10
@test get_line_offsets(d2) == [0, 8, 15]
@test get_position_at(d2, 1) == (0, 1)
@test get_position_at(d2, 9) == (1, 1)
@test get_position_at(d2, 17) == (2, 2)
@test is_workspace_file(d2) == true


applytextdocumentchanges(d2, LanguageServer.TextDocumentContentChangeEvent(Range(1), 0, "12"))
@test get_line_offsets(d2) == [0, 8, 17]

s4 = "1234\r\nabcd"
d4 = Document("untitled", s4, false)
@test_broken get_line_offsets(d4) == [0, 5]

s5 = "1234\nabcd\n"
d5 = Document("untitled", s5, false)
@test get_line_offsets(d5) == [0, 5, 10]

s6 = "\n"
d6 = Document("untitled", s6, false)
@test get_line_offsets(d6) == [0,1]

@testset "applytextdocumentchanges" begin
    doc = LS.Document("file:///example/path/example.jl", "function foo()", false)
    c1 = LS.TextDocumentContentChangeEvent(LS.Range(LS.Position(0, 14), LS.Position(0, 14)),
                                        0, "\n")
    c2 = LS.TextDocumentContentChangeEvent(LS.Range(LS.Position(1, 0), LS.Position(1, 0)),
                                           0, "    ")
    c3 = LS.TextDocumentContentChangeEvent(missing, missing, "println(\"Hello World\")")

    LS.applytextdocumentchanges(doc, c1)
    @test LS.get_text(doc) == "function foo()\n"
    # Implicitly test for issue #403
    LS.applytextdocumentchanges(doc, c2)
    @test LS.get_text(doc) == "function foo()\n    "
    LS.applytextdocumentchanges(doc, c3)
    @test LS.get_text(doc) == "println(\"Hello World\")"
    # doc currently has only one line, applying change to 2nd line should throw
    @test_throws LanguageServer.LSOffsetError LS.applytextdocumentchanges(doc, c2)
end

@testset "UTF16 handling" begin
    doc = LanguageServer.Document("", "aaa", false)
    @test sizeof(LanguageServer.get_text(doc)) == 3
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_at(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 1) == 1
    @test LanguageServer.get_position_at(doc, 1) == (0, 1)
    @test LanguageServer.get_offset(doc, 0, 2) == 2
    @test LanguageServer.get_position_at(doc, 2) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 3) == 3
    @test LanguageServer.get_position_at(doc, 3) == (0, 3)


    doc = LanguageServer.Document("", "ααα", false)
    @test sizeof(LanguageServer.get_text(doc)) == 6
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_at(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 1) == 1
    @test LanguageServer.get_position_at(doc, 1) == (0, 1)
    @test LanguageServer.get_offset(doc, 0, 2) == 3
    @test LanguageServer.get_position_at(doc, 3) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 3) == 5
    @test LanguageServer.get_position_at(doc, 5) == (0, 3)

    doc = LanguageServer.Document("", "ࠀࠀࠀ", false) # 0x0800
    @test sizeof(LanguageServer.get_text(doc)) == 9
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_at(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 1) == 1
    @test LanguageServer.get_position_at(doc, 1) == (0, 1)
    @test LanguageServer.get_offset(doc, 0, 2) == 4
    @test LanguageServer.get_position_at(doc, 4) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 3) == 7
    @test LanguageServer.get_position_at(doc, 7) == (0, 3)

    doc = LanguageServer.Document("", "𐐀𐐀𐐀", false)
    @test sizeof(LanguageServer.get_text(doc)) == 12
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_at(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 2) == 1
    @test LanguageServer.get_position_at(doc, 1) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 4) == 5
    @test LanguageServer.get_position_at(doc, 5) == (0, 4)
    @test LanguageServer.get_offset(doc, 0, 6) == 9
    @test LanguageServer.get_position_at(doc, 9) == (0, 6)

    doc = LanguageServer.Document("", "𐀀𐀀𐀀", false) # 0x010000
    @test sizeof(LanguageServer.get_text(doc)) == 12
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_at(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 2) == 1
    @test LanguageServer.get_position_at(doc, 1) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 4) == 5
    @test LanguageServer.get_position_at(doc, 5) == (0, 4)
    @test LanguageServer.get_offset(doc, 0, 6) == 9
    @test LanguageServer.get_position_at(doc, 9) == (0, 6)
end
