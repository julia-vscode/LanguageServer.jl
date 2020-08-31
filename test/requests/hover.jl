hover_test(line, char) = LanguageServer.textDocument_hover_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)

settestdoc("""
1234
Base
+
vari = 1234
\"\"\"
    Text
\"\"\"
function func(arg) end
func() = nothing
module M end
struct T end
mutable struct T end
for i = 1:1 end
while true end
begin end
sin()
""")

@test hover_test(0, 1) === nothing
@test hover_test(1, 1) !== nothing
@test hover_test(2, 1) !== nothing
@test hover_test(3, 1) !== nothing
@test hover_test(7, 11) !== nothing
@test hover_test(8, 2) !== nothing
@test hover_test(7, 16) !== nothing
@test hover_test(7, 20) !== nothing
@test hover_test(9, 11) !== nothing
@test hover_test(10, 11) !== nothing
@test hover_test(11, 18) !== nothing
@test hover_test(12, 14) !== nothing
@test hover_test(13, 13) !== nothing
@test hover_test(14, 7) !== nothing
@test hover_test(15, 5) !== nothing
