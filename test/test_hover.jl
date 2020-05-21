server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true

LanguageServer.initialize_request(nothing, init_request, server)

testtext = """
module testmodule
struct testtype
    a
    b::Float64
    c::Vector{Float64}
end
function testfunction(a, b::Float64, c::testtype)
    return c
end
end
testmodule
"""
LanguageServer.textDocument_didOpen_notification(nothing, LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("testdoc", "julia", 0, testtext)), server)

doc = LanguageServer.getdocument(server, LanguageServer.URI2("testdoc"))
LanguageServer.parse_all(doc, server)


res = LanguageServer.textDocument_hover_request(nothing, LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(3, 11)), server)
@test res.contents.value == string(LanguageServer.sanitize_docstring(StaticLint.CoreTypes.Float64.doc), "\n```julia\nCore.Float64 <: Core.AbstractFloat\n```")

res = LanguageServer.textDocument_hover_request(nothing, LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(7, 12)), server)
@test occursin(r"c::testtype", res.contents.value)

res = LanguageServer.textDocument_hover_request(nothing, LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(9, 1)), server)
@test res.contents.value == "Closes module definition for `testmodule`\n"
