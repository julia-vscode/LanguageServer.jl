import LanguageServer: LanguageServerInstance, Document
server = LanguageServerInstance(IOBuffer(), IOBuffer(), false)
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

server.documents[LanguageServer.URI2("testdoc")] = Document("testdoc", testtext, true)
doc = server.documents[LanguageServer.URI2("testdoc")]
LanguageServer.parse_all(doc, server)

# clear init output
take!(server.pipe_out)

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":3,"character":11}}}""")), server)
res = getresult(server)
@test startswith(res[1]["value"], "\nFloat64")

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":8,"character":12}}}""")), server)
res = getresult(server)
@test res[1]["value"] == "testtype"


LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":10,"character":1}}}""")), server)
res = getresult(server)
@test res[1]["value"] == "Closes `module` expression"
