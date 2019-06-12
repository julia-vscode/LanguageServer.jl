import LanguageServer: Document, get_text, get_offset, get_line_offsets, get_position_at, get_open_in_editor, set_open_in_editor, is_workspace_file, applytextdocumentchanges

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
@test_broken get_line_offsets(d2) == [0, 8, 17]

s4 = "1234\r\nabcd"
d4 = Document("untitled", s4, false)
@test_broken get_line_offsets(d4) == [0, 5]

s5 = "1234\nabcd\n"
d5 = Document("untitled", s5, false)
@test get_line_offsets(d5) == [0, 5, 10]

s6 = "\n"
d6 = Document("untitled", s6, false)
@test get_line_offsets(d6) == [0,1]

