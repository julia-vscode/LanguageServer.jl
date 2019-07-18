import LanguageServer: LanguageServerInstance, Document, Pkg
using LanguageServer, CSTParser, StaticLint, SymbolServer

server = LanguageServerInstance(IOBuffer(), IOBuffer(), true, dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH), Dict())
@async run(server)
t = time()
while server.symbol_server isa Nothing && time() - t < 60
    sleep(1)
end

server.runlinter = true
LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse(init_request)), server)


function getresult(server)
    str = String(take!(server.pipe_out))
    JSON.parse(str[findfirst("{", str)[1]:end])["result"]["contents"]
end

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

doc = server.documents[LanguageServer.URI2("testdoc")]
LanguageServer.parse_all(doc, server)

# clear init output
take!(server.pipe_out)

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":3,"character":11}}}""")), server)
res = getresult(server)
@test res[1] == server.symbol_server.depot["Core"].vals["Float64"].doc


LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":8,"character":12}}}""")), server)
res = getresult(server)
@test res[1]["value"] == "c::testtype"


LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":10,"character":1}}}""")), server)
res = getresult(server)
@test res[1]["value"] == "Closes ModuleH expression."
