import LanguageServer.Document
import LanguageServer.get_text
import LanguageServer.get_line
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
@test get_line(d1,1) == "123456\n"
@test get_line(d1,2) == "abcde\n"
@test get_line(d1,3) == "ABCDEFG\n"
@test get_offset(d1,1,4) == chr2ind(d1._content,4)
@test get_offset(d1,2,2) == chr2ind(d1._content,9)
@test get_line_offsets(d1) == [chr2ind(d1._content,1),chr2ind(d1._content,8),chr2ind(d1._content,14),chr2ind(d1._content,21)+1]
@test get_position_at(d1,1) == (1,1)
@test get_position_at(d1,8) == (2,1)
@test get_position_at(d1,15) == (3,2)
@test get_open_in_editor(d1)==false
set_open_in_editor(d1, true)
@test get_open_in_editor(d1)==true
set_open_in_editor(d1, false)
@test get_open_in_editor(d1)==false
@test is_workspace_file(d1)==false


s2 = """
12μ456
abηde
ABCDEFG"""
d2 = Document("untitled", s2, true)
@test get_line(d2,1) == "12μ456\n"
@test get_line(d2,2) == "abηde\n"
@test get_line(d2,3) == "ABCDEFG"
@test get_offset(d2,1,4) == chr2ind(d2._content,4)
@test get_offset(d2,2,2) == chr2ind(d2._content,9)
@test get_line_offsets(d2) == [chr2ind(d2._content,1),chr2ind(d2._content,8),chr2ind(d2._content,14)]
@test get_position_at(d2,chr2ind(d2._content,1)) == (1,1)
@test get_position_at(d2,chr2ind(d2._content,8)) == (2,1)
@test get_position_at(d2,chr2ind(d2._content,15)) == (3,2)
@test is_workspace_file(d2)==true


update(d2, 2, 2, 0, "12")
@test get_line(d2,1) == "12μ456\n"
@test get_line(d2,2) == "a12bηde\n"
@test get_line(d2,3) == "ABCDEFG"
@test get_line_offsets(d2) == [chr2ind(d2._content,1),chr2ind(d2._content,8),chr2ind(d2._content,16)]

update(d2, 1, 3, 3, "abcdef")
@test get_line(d2,1) == "12abcdef6\n"
@test get_line(d2,2) == "a12bηde\n"
@test get_line(d2,3) == "ABCDEFG"
@test get_line_offsets(d2) == [chr2ind(d2._content,1),chr2ind(d2._content,11),chr2ind(d2._content,19)]

update(d2, 2, 5, 4, "xyz")
@test get_line(d2,1) == "12abcdef6\n"
@test get_line(d2,2) == "a12bxyzABCDEFG"
@test get_line_offsets(d2) == [chr2ind(d2._content,1),chr2ind(d2._content,11)]

update(d2,1,1,0,"PRE")
@test get_text(d2) == "PRE12abcdef6\na12bxyzABCDEFG"

update(d2,2,15,0,"POST")
@test get_text(d2) == "PRE12abcdef6\na12bxyzABCDEFGPOST"


s3 = ""
d3 = Document("untitled", s3, false)
@test get_line(d3,1) == ""
update(d3,1,1,0,"a")
@test get_line(d3,1) == "a"

s4 = "1234\r\nabcd"
d4 = Document("untitled", s4, false)
@test get_line(d4,1) == "1234\r\n"
@test get_line(d4,2) == "abcd"
@test get_line_offsets(d4) == [1,7]

s5 = "1234\nabcd\n"
d5 = Document("untitled", s5, false)
@test get_line(d5,1) == "1234\n"
@test get_line(d5,2) == "abcd\n"
@test get_line_offsets(d5) == [1,6,11]

s6 = "\n"
d6 = Document("untitled", s6, false)
@test get_line_offsets(d6) == [1,2]
@test get_line(d6,1) == "\n"
