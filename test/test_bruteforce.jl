using LanguageServer
for n in names(LanguageServer, true, true)
    eval(:(import LanguageServer.$n))
end
import LanguageServer.JSONRPC:Request, parse
Range = LanguageServer.Range

server = LanguageServerInstance(IOBuffer(), IOBuffer(), true)
process(parse(Request, """{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"processId":6729,"rootPath":"$(Pkg.dir("LanguageServer"))","capabilities":{},"trace":"off"}}"""), server)
process(parse(Request, """{"jsonrpc":"2.0","method":"\$/setTraceNotification","params":{"value":"off"}}"""), server)
process(parse(Request, """{"jsonrpc":"2.0","method":"workspace/didChangeConfiguration","params":{"settings":{}}}"""), server)





function test(uri, method, server)
    text =readstring(uri[8:end])
    server.debug_mode = false
    r = parse(Request, """{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$uri","languageId":"julia","version":1,"text":""}}}""")
    r.params.textDocument.text = text
    process(r, server)
    doc = server.documents[uri]
    get_line_offsets(doc::Document)    
    nl =  length(doc._line_offsets.value)-1
    nc = diff(doc._line_offsets.value)-1

    r = parse(Request, """{"jsonrpc":"2.0","id":1,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"$uri"}}}""")
    process(r, server)
    for l = 0:nl-1
        for c = 0:nc[l+1]
            try
                r = parse(Request, """{"jsonrpc":"2.0","id":2,"method":"$method","params":{"textDocument":{"uri":"$uri"},"position":{"line":$l,"character":$c}}}""")
                process(r, server)
            catch e
                println(l, ":", c)
                error(e)
            end
        end
    end
    server.debug_mode = true
end


allmethods = ["textDocument/hover"
              "textDocument/completions"
              "textDocument/signatureHelp"
              "textDocument/definition"] 


for uri in collect(filter(f->ismatch(r"/src/", f), keys(server.documents)))
    for m in allmethods
        print(uri, "   ")
        test(uri, m, server)
    end
end



