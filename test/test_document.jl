import LanguageServer.Document
import LanguageServer.get_text
import LanguageServer.update
import LanguageServer.get_offset
import LanguageServer.get_line_offsets
import LanguageServer.get_position_at
import LanguageServer.get_open_in_editor
import LanguageServer.set_open_in_editor
import LanguageServer.is_workspace_file

s1 = """
123456
abcde
ABCDEFG
"""
d1 = Document("untitled", s1, false)
@test get_text(d1) == s1
@test get_offset(d1, 0, 4) == 4
@test get_offset(d1, 1, 2) == 9
@test get_line_offsets(d1) == [1, 8, 14, 21 + 1]
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
@test get_line_offsets(d2) == [1, 9, 16]
@test get_line_offsets(d2) == [nextind(d2._content,0,1), nextind(d2._content,0,8), nextind(d2._content,0,14)]
@test get_position_at(d2, 1) == (0, 1)
@test get_position_at(d2, 9) == (1, 1)
@test get_position_at(d2, 17) == (2, 2)
@test is_workspace_file(d2) == true


update(d2, 2, 2, 0, "12")
@test get_line_offsets(d2) == [nextind(d2._content, 0, 1), nextind(d2._content, 0, 8), nextind(d2._content, 0, 16)]

update(d2, 1, 3, 3, "abcdef")
@test get_line_offsets(d2) == [nextind(d2._content, 0, 1), nextind(d2._content, 0, 11), nextind(d2._content, 0, 19)]

update(d2, 2, 5, 4, "xyz")
@test get_line_offsets(d2) == [nextind(d2._content, 0, 1), nextind(d2._content, 0, 11)]

update(d2, 1, 1, 0, "PRE")
@test get_text(d2) == "PRE12abcdef6\na12bxyzABCDEFG"

update(d2, 2, 15, 0, "POST")
@test get_text(d2) == "PRE12abcdef6\na12bxyzABCDEFGPOST"



s4 = "1234\r\nabcd"
d4 = Document("untitled", s4, false)
@test get_line_offsets(d4) == [1, 7]

s5 = "1234\nabcd\n"
d5 = Document("untitled", s5, false)
@test get_line_offsets(d5) == [1, 6, 11]

s6 = "\n"
d6 = Document("untitled", s6, false)
@test get_line_offsets(d6) == [1, 2]

