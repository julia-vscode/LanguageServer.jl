server = LanguageServerInstance(IOBuffer(), IOBuffer(), false, dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, Dict("jsonrpc" => "2.0", "id" => 0, "method" => "initialize", "params" => init_request)), server)

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
LanguageServer.process(LanguageServer.JSONRPC.Request{Val{Symbol("textDocument/didOpen")},LanguageServer.DidOpenTextDocumentParams}(0, LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("testdoc", "julia", 0, testtext))), server)

doc = LanguageServer.getdocument(server, LanguageServer.URI2("testdoc"))
LanguageServer.parse_all(doc, server)


res = LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":3,"character":11}}}""")), server)
@test res.contents.value == LanguageServer.sanitize_docstring(StaticLint.CoreTypes.Float64.doc)

res = LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":7,"character":12}}}""")), server)
@test occursin(r"c::testtype", res.contents.value)

res = LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":9,"character":1}}}""")), server)
@test res.contents.value == "Closes `ModuleH` expression."
