@testitem "document 1" begin
    using LanguageServer.URIs2
    using LanguageServer: TextDocument, Document, set_open_in_editor, is_workspace_file, get_open_in_editor, get_position_from_offset, get_text_document, get_line_offsets, get_offset, get_text

    s1 = """
    123456
    abcde
    ABCDEFG
    """
    d1 = Document(TextDocument(uri"untitled:none", s1, 0), false)
    @test get_text(d1) == s1
    @test get_offset(d1, 0, 4) == 4
    @test get_offset(d1, 1, 2) == 9
    @test get_line_offsets(get_text_document(d1)) == [0, 7, 13, 21]
    @test get_position_from_offset(d1, 1) == (0, 1)
    @test get_position_from_offset(d1, 8) == (1, 1)
    @test get_position_from_offset(d1, 15) == (2, 2)
    @test get_open_in_editor(d1) == false
    set_open_in_editor(d1, true)
    @test get_open_in_editor(d1) == true
    set_open_in_editor(d1, false)
    @test get_open_in_editor(d1) == false
    @test is_workspace_file(d1) == false
end

@testitem "document 2" begin
    using LanguageServer.URIs2
    using LanguageServer: TextDocument, Document, get_text_document, set_text_document!, Range, apply_text_edits, get_line_offsets, is_workspace_file, get_position_from_offset, get_offset

    s2 = """
    12μ456
    abηde
    ABCDEFG"""
    d2 = Document(TextDocument(uri"untitled:none", s2, 0), true)
    @test get_offset(d2, 0, 4) == 5
    @test get_offset(d2, 1, 2) == 10
    @test get_line_offsets(get_text_document(d2)) == [0, 8, 15]
    @test get_position_from_offset(d2, 1) == (0, 1)
    @test get_position_from_offset(d2, 9) == (1, 1)
    @test get_position_from_offset(d2, 17) == (2, 2)
    @test is_workspace_file(d2) == true


    set_text_document!(d2, apply_text_edits(get_text_document(d2), [LanguageServer.TextDocumentContentChangeEvent(Range(1), 0, "12")], 1))
    @test get_line_offsets(get_text_document(d2)) == [0, 8, 17]
end

@testitem "document 3" begin
    using LanguageServer.URIs2
    using LanguageServer: TextDocument, Document

    s4 = "1234\r\nabcd"
    d4 = Document(TextDocument(uri"untitled:none", s4, 0), false)
    @test_broken get_line_offsets(get_text_document(d4)) == [0, 5]
end

@testitem "document 4" begin
    using LanguageServer.URIs2
    using LanguageServer: TextDocument, Document, get_line_offsets, get_text_document

    s5 = "1234\nabcd\n"
    d5 = Document(TextDocument(uri"untitled:none", s5, 0), false)
    @test get_line_offsets(get_text_document(d5)) == [0, 5, 10]
end

@testitem "document 5" begin
    using LanguageServer.URIs2
    using LanguageServer: TextDocument, Document, get_line_offsets, get_text_document

    s6 = "\n"
    d6 = Document(TextDocument(uri"untitled:none", s6, 0), false)
    @test get_line_offsets(get_text_document(d6)) == [0, 1]
end

@testitem "apply_text_edits" begin
    using LanguageServer.URIs2
    using LanguageServer: TextDocument, TextDocumentContentChangeEvent, Range, Position, apply_text_edits, LSOffsetError, apply_text_edits, get_text

    version = 0
    doc = TextDocument(uri"file:///example/path/example.jl", "function foo()", version)
    c1 = TextDocumentContentChangeEvent(Range(Position(0, 14), Position(0, 14)), 0, "\n")
    c2 = TextDocumentContentChangeEvent(Range(Position(1, 0), Position(1, 0)), 0, "    ")
    c3 = TextDocumentContentChangeEvent(missing, missing, "println(\"Hello World\")")

    doc = apply_text_edits(doc, [c1], version += 1)
    @test get_text(doc) == "function foo()\n"
    # Implicitly test for issue #403
    doc = apply_text_edits(doc, [c2], version += 1)
    @test get_text(doc) == "function foo()\n    "
    doc = apply_text_edits(doc, [c3], version += 1)
    @test get_text(doc) == "println(\"Hello World\")"

    # Test muliple edits (#1118)
    doc = TextDocument(uri"file:///example/path/example.jl", "module Crash\n\n\n\nend # module Crash\n", version)
    edits = [
        TextDocumentContentChangeEvent(Range(Position(2, 0), Position(2, 0)), 0, "p"),
        TextDocumentContentChangeEvent(Range(Position(2, 1), Position(2, 1)), 0, "r"),
        TextDocumentContentChangeEvent(Range(Position(2, 2), Position(2, 2)), 0, "i"),
        TextDocumentContentChangeEvent(Range(Position(2, 3), Position(2, 3)), 0, "n"),
        TextDocumentContentChangeEvent(Range(Position(2, 4), Position(2, 4)), 0, "t"),
    ]
    doc = apply_text_edits(doc, edits, version += 1)
    @test get_text(doc) == "module Crash\n\nprint\n\nend # module Crash\n"

    # doc currently has only one line, applying change to 2nd line should throw
    doc = apply_text_edits(doc, [c3], version += 1)
    @test_throws LSOffsetError apply_text_edits(doc, [c2], version + 1)
end

@testitem "UTF16 handling" begin
    using LanguageServer.URIs2
    using LanguageServer: TextDocument, Document

    doc = LanguageServer.Document(TextDocument(uri"", "aaa", 0), false)
    @test sizeof(LanguageServer.get_text(doc)) == 3
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_from_offset(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 1) == 1
    @test LanguageServer.get_position_from_offset(doc, 1) == (0, 1)
    @test LanguageServer.get_offset(doc, 0, 2) == 2
    @test LanguageServer.get_position_from_offset(doc, 2) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 3) == 3
    @test LanguageServer.get_position_from_offset(doc, 3) == (0, 3)


    doc = LanguageServer.Document(TextDocument(uri"", "ααα", 0), false)
    @test sizeof(LanguageServer.get_text(doc)) == 6
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_from_offset(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 1) == 1
    @test LanguageServer.get_position_from_offset(doc, 1) == (0, 1)
    @test LanguageServer.get_offset(doc, 0, 2) == 3
    @test LanguageServer.get_position_from_offset(doc, 3) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 3) == 5
    @test LanguageServer.get_position_from_offset(doc, 5) == (0, 3)

    doc = LanguageServer.Document(TextDocument(uri"", "ࠀࠀࠀ", 0), false) # 0x0800
    @test sizeof(LanguageServer.get_text(doc)) == 9
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_from_offset(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 1) == 1
    @test LanguageServer.get_position_from_offset(doc, 1) == (0, 1)
    @test LanguageServer.get_offset(doc, 0, 2) == 4
    @test LanguageServer.get_position_from_offset(doc, 4) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 3) == 7
    @test LanguageServer.get_position_from_offset(doc, 7) == (0, 3)

    doc = LanguageServer.Document(TextDocument(uri"", "𐐀𐐀𐐀", 0), false)
    @test sizeof(LanguageServer.get_text(doc)) == 12
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_from_offset(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 2) == 1
    @test LanguageServer.get_position_from_offset(doc, 1) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 4) == 5
    @test LanguageServer.get_position_from_offset(doc, 5) == (0, 4)
    @test LanguageServer.get_offset(doc, 0, 6) == 9
    @test LanguageServer.get_position_from_offset(doc, 9) == (0, 6)

    doc = LanguageServer.Document(TextDocument(uri"", "𐀀𐀀𐀀", 0), false) # 0x010000
    @test sizeof(LanguageServer.get_text(doc)) == 12
    @test LanguageServer.get_offset(doc, 0, 0) == 0
    @test LanguageServer.get_position_from_offset(doc, 0) == (0, 0)
    @test LanguageServer.get_offset(doc, 0, 2) == 1
    @test LanguageServer.get_position_from_offset(doc, 1) == (0, 2)
    @test LanguageServer.get_offset(doc, 0, 4) == 5
    @test LanguageServer.get_position_from_offset(doc, 5) == (0, 4)
    @test LanguageServer.get_offset(doc, 0, 6) == 9
    @test LanguageServer.get_position_from_offset(doc, 9) == (0, 6)
end

@testitem "document link provider" begin
    using LanguageServer: TextDocument, Document, filepath2uri, DocumentLink, getcst, find_document_links

    doc = Document(TextDocument(filepath2uri(@__FILE__), """
    include("test_document.jl")
    include("runtests_does_not_exist.jl")
    """, 0), false)
    links = DocumentLink[]
    find_document_links(getcst(doc), doc, 0, links)
    @test length(links) == 1
    @test links[1].target == filepath2uri(@__FILE__)
end

@testitem "Base.show for (Text)Document" begin
    using LanguageServer: TextDocument

    tdoc = TextDocument(LanguageServer.URIs2.URI("file:///tmp/foo.jl"), "foo", 0)
    @test sprint(show, MIME("text/plain"), tdoc) == "TextDocument: file:///tmp/foo.jl"
    doc = LanguageServer.Document(tdoc, false)
    @test sprint(show, MIME("text/plain"), doc) == "Document: file:///tmp/foo.jl"
end
