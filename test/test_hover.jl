import LanguageServer: LanguageServerInstance, Document, parseblocks
server = LanguageServerInstance(IOBuffer(), IOBuffer(), false)

function getresult(server)
    str = String(take!(server.pipe_out))
    JSON.parse(str[search(str,'{'):end])["result"]["contents"]
end

testtext="""module testmodule
type testtype
    a
    b::Float64
    c::Vector{Float64}
end

function testfunction(a, b::Float64, c::testtype)
    return c
end
end
"""

server.documents["testdoc"] = Document("testdoc",testtext,true)
doc = server.documents["testdoc"]
parseblocks(doc, server)

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, """{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":0,"character":12}}}"""), server)

res = getresult(server)

@test res[1]=="Module"

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, """{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":1,"character":9}}}"""), server)

res = getresult(server)

@test res[1]=="DataType"
@test res[2]["value"]=="type testtype\n    a\n    b::Float64\n    c::Vector{Float64}\nend"

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, """{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":7,"character":19}}}"""), server)

res = getresult(server)

@test res[1]["value"]=="Function"