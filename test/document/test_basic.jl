using Test
import LanguageServer: Document, Range, Position,
                       get_text, get_offset, get_line_offsets, get_position_at,
                       get_open_in_editor, set_open_in_editor,
                       is_workspace_file, 
                       applytextdocumentchanges, TextDocumentContentChangeEvent

text1 = """
123456
abcde
ABCDEFG
"""
doc1 = Document("untitled", text1, false)

text2 = """
12μ456
abηde
ABCDEFG"""
doc2 = Document("untitled", text2, true)

@testset "Basic operations" begin
    @testset "Document 1" begin
        
        @test get_text(doc1) == text1
        @test get_offset(doc1, 0, 4) == 4
        @test get_offset(doc1, 1, 2) == 9
        @test get_line_offsets(doc1) == [0, 7, 13, 21]
        @test get_position_at(doc1, 1) == (0, 1)
        @test get_position_at(doc1, 8) == (1, 1)
        @test get_position_at(doc1, 15) == (2, 2)
    
    end

    @testset "Dcoument 2" begin

        @test get_offset(doc2, 0, 4) == 5
        @test get_offset(doc2, 1, 2) == 10
        @test get_line_offsets(doc2) == [0, 8, 15]
        @test get_position_at(doc2, 1) == (0, 1)
        @test get_position_at(doc2, 9) == (1, 1)
        @test get_position_at(doc2, 17) == (2, 2)

    end

    @testset "Workspace" begin

        @test is_workspace_file(doc1) == false
        @test is_workspace_file(doc2) == true

        @test get_open_in_editor(doc1) == false
        set_open_in_editor(doc1, true)
        @test get_open_in_editor(doc1) == true
        set_open_in_editor(doc1, false)
        @test get_open_in_editor(doc1) == false
        
    end

    @testset "Document changes" begin
        
        new_text2 = """
        12μ456
        12abηde
        ABCDEFG"""
        applytextdocumentchanges(doc2, TextDocumentContentChangeEvent(Range(1), 0, "12"))

        @test get_text(doc2) == new_text2
        @test get_line_offsets(doc2) == [0, 8, 17]
    
    end

    @testset "Breaklines" begin

        text = "\n"
        breakline_doc = Document("untitled", text, false)
        @test get_line_offsets(breakline_doc) == [0,1]

        text = "1234\r\nabcd"
        breakline_doc = Document("untitled", text, false)
        @test_broken get_line_offsets(breakline_doc) == [0, 5]

        text = "1234\nabcd\n"
        breakline_doc = Document("untitled", text, false)
        @test get_line_offsets(breakline_doc) == [0, 5, 10]

    end

    @testset "whitespaces" begin

        text = " \n"
        whitespaces_doc = Document("untitled", text, false)
        @test get_line_offsets(whitespaces_doc) == [0,2]

        text = "\n "
        whitespaces_doc = Document("untitled", text, false)
        @test get_line_offsets(whitespaces_doc) == [0, 1]

        text = " \n \n "
        whitespaces_doc = Document("untitled", text, false)
        @test get_line_offsets(whitespaces_doc) == [0, 2, 4]

    end

end