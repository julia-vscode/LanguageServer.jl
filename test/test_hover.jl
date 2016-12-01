import LanguageServer: LanguageServerInstance, Document, parseblocks
server = LanguageServerInstance(IOBuffer(), IOBuffer(), false)

function getresult(server)
    str = takebuf_string(server.pipe_out)
    JSON.parse(str[search(str,'{'):end])["result"]["contents"]
end

testtext="""module testmodule
type testtype
    a
    b::Int
    c::Vector{Int}
end

function testfunction(a, b::Int, c::testtype)
    return c
end
end
"""

server.documents["testdoc"] = Document(testtext)
doc = server.documents["testdoc"]
parseblocks(doc, server)

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, """{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":0,"character":12}}}"""), server)

res = getresult(server)

@test res[1]["value"]=="global: Module at 1"
@test res[2]["value"]==testtext[1:17]

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, """{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":1,"character":9}}}"""), server)

res = getresult(server)

@test res[1]["value"]=="global: DataType at 2"
@test res[2]["value"]=="    a::Any"
@test res[3]["value"]=="    b::Int"
@test res[4]["value"]=="    c::Vector{Int}"

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, """{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"testdoc"},"position":{"line":3,"character":9}}}"""), server)

res = getresult(server)

@test res[1]["value"]=="Int64 <: Signed"