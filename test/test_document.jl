import LanguageServer.Document
import LanguageServer.get_line
import LanguageServer.update
import LanguageServer.get_offset
import LanguageServer.get_line_offsets

s1 = """
123456
abcde
ABCDEFG
"""
d1 = Document(s1)
@test get_line(d1,1) == "123456\n"
@test get_line(d1,2) == "abcde\n"
@test get_line(d1,3) == "ABCDEFG\n"
@test get_offset(d1,1,4) == chr2ind(d1._content,4) 
@test get_offset(d1,2,2) == chr2ind(d1._content,9)
@test get_line_offsets(d1) == [chr2ind(d1._content,1),chr2ind(d1._content,8),chr2ind(d1._content,14)]

s2 = """
12μ456
abηde
ABCDEFG"""
d2 = Document(s2)
@test get_line(d2,1) == "12μ456\n"
@test get_line(d2,2) == "abηde\n"
@test get_line(d2,3) == "ABCDEFG"
@test get_offset(d2,1,4) == chr2ind(d2._content,4) 
@test get_offset(d2,2,2) == chr2ind(d2._content,9)
@test get_line_offsets(d2) == [chr2ind(d2._content,1),chr2ind(d2._content,8),chr2ind(d2._content,14)]

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
