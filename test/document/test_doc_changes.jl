using Test
import LanguageServer: Document, Range, Position,
                       get_text, get_offset, get_line_offsets, get_position_at,
                       get_open_in_editor, set_open_in_editor,
                       is_workspace_file, 
                       applytextdocumentchanges, TextDocumentContentChangeEvent

@testset "Document changes" begin
    doc = Document("file:///example/path/example.jl", "function foo()", false)
    c1 = TextDocumentContentChangeEvent(Range(Position(0,14), Position(0,14)),
                                        0, "\n")
    c2 = TextDocumentContentChangeEvent(Range(Position(1,0), Position(1,0)),
                                        0, "    ")
    c3 = TextDocumentContentChangeEvent(missing, missing, "println(\"Hello World\")")

    applytextdocumentchanges(doc, c1)
    @test get_text(doc) == "function foo()\n"
    # Implicitly test for issue #403
    applytextdocumentchanges(doc, c2)
    @test get_text(doc) == "function foo()\n    "
    applytextdocumentchanges(doc, c3)
    @test get_text(doc) == "println(\"Hello World\")"
    # doc currently has only one line, applying change to 2nd line should throw
    @test_throws BoundsError applytextdocumentchanges(doc, c2)
end

