s1 = """
123456
abcde
ABCDEFG
"""
d1 = LanguageServer.Document(s1)
@test LanguageServer.get_line(d1,1) == "123456\n"
@test LanguageServer.get_line(d1,2) == "abcde\n"
@test LanguageServer.get_line(d1,3) == "ABCDEFG\n"

s2 = """
12μ456
abηde
ABCDEFG"""
d2 = LanguageServer.Document(s2)
@test LanguageServer.get_line(d2,1) == "12μ456\n"
@test LanguageServer.get_line(d2,2) == "abηde\n"
@test LanguageServer.get_line(d2,3) == "ABCDEFG"

LanguageServer.update(d2, 2, 2, 2, 4, "12")
@test LanguageServer.get_line(d2,1) == "12μ456\n"
@test LanguageServer.get_line(d2,2) == "ab12e\n"
@test LanguageServer.get_line(d2,3) == "ABCDEFG"

LanguageServer.update(d2, 1, 3, 1, 3, "abcdef")
@test LanguageServer.get_line(d2,1) == "12μabcdef456\n"
@test LanguageServer.get_line(d2,2) == "ab12e\n"
@test LanguageServer.get_line(d2,3) == "ABCDEFG"