using LanguageServer, Pkg
import LanguageServer.JSONRPC: Request, parse
import LanguageServer: process
server = LanguageServerInstance(IOBuffer(), IOBuffer(), false, dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.symbol_server = LanguageServer.SymbolServer.SymbolServerProcess()
init_request = """
{
    "jsonrpc":"2.0",
    "id":0,
    "method":"initialize",
    "params":{"processId":9902,
              "rootPath":null,
              "rootUri":"$(Pkg.dir("LanguageServer"))",
              "capabilities":{"workspace":{"applyEdit":true,"workspaceEdit":{"documentChanges":true},"didChangeConfiguration":{"dynamicRegistration":false},"didChangeWatchedFiles":{"dynamicRegistration":false},"symbol":{"dynamicRegistration":true},"executeCommand":{"dynamicRegistration":true}},"textDocument":{"synchronization":{"dynamicRegistration":true,"willSave":true,"willSaveWaitUntil":true,"didSave":true},"completion":{"dynamicRegistration":true,"completionItem":{"snippetSupport":true}},"hover":{"dynamicRegistration":true},"signatureHelp":{"dynamicRegistration":true},"references":{"dynamicRegistration":true},"documentHighlight":{"dynamicRegistration":true},"documentSymbol":{"dynamicRegistration":true},"formatting":{"dynamicRegistration":true},"rangeFormatting":{"dynamicRegistration":true},"onTypeFormatting":{"dynamicRegistration":true},"definition":{"dynamicRegistration":true},"codeAction":{"dynamicRegistration":true},"codeLens":{"dynamicRegistration":true},"documentLink":{"dynamicRegistration":true},"rename":{"dynamicRegistration":true}}},
              "trace":"off"}
}"""

process(LanguageServer.parse(Request, LanguageServer.JSON.parse(init_request)), server)
process(LanguageServer.parse(Request, LanguageServer.JSON.parse("""{"jsonrpc":"2.0","method":"initialized","params":{}}""")), server)
server.debug_mode = false

# Workspace Symbols
r = parse(Request, LanguageServer.JSON.parse("""{"jsonrpc":"2.0","id":59,"method":"workspace/symbol","params":{"query":""}}"""))
process(r, server);

# Document Symbols
for doc in LanguageServer.getdocuments_value(server)
    uri = doc._uri
    r = parse(Request, LanguageServer.JSON.parse("""{"jsonrpc":"2.0","id":1,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"$(uri)"}}}"""))
    process(r, server)
end

# Hovers

for doc in LanguageServer.getdocuments_value(server)
    uri = doc._uri
    print("Hovers: $uri ")
    for loc in 1:sizeof(LanguageServer.get_text(doc))-1
        line, character = LanguageServer.get_position_at(doc, loc)
        r = parse(Request, LanguageServer.JSON.parse("""{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$uri"},"position":{"line":$line,"character":$character}}}"""))
        process(r, server)
    end
end

# Completions
for doc in LanguageServer.getdocuments_value(server)
    uri = doc._uri
    print("Completions: $uri ")
    for loc in 1:sizeof(LanguageServer.get_text(doc))-1
        mod(loc,100)==0 && println(loc/sizeof(doc._content))
        line, character = LanguageServer.get_position_at(doc, loc)
        r = parse(Request, LanguageServer.JSON.parse("""{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$uri"},"position":{"line":$line,"character":$character}}}"""))
        process(r, server)
    end
end

# Definitions
for doc in LanguageServer.getdocuments_value(server)
    uri = doc._uri
    print("Definitions: $uri ")
    for loc in 1:sizeof(LanguageServer.get_text(doc))-1
        mod(loc,100)==0 && println(loc/sizeof(doc._content))
        line, character = LanguageServer.get_position_at(doc, loc)
        r = parse(Request, LanguageServer.JSON.parse("""{"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$uri"},"position":{"line":$line,"character":$character}}}"""))
        process(r, server)
    end
end

# Signatures
for doc in LanguageServer.getdocuments_value(server)
    uri = doc._uri
    print("Signatures: $uri ")
    for loc in 1:sizeof(LanguageServer.get_text(doc))-1
        mod(loc,100)==0 && println(loc/sizeof(doc._content))
        line, character = LanguageServer.get_position_at(doc, loc)
        r = parse(Request, (LanguageServer.JSON.parse("""{"jsonrpc":"2.0","id":2,"method":"textDocument/signatureHelp","params":{"textDocument":{"uri":"$uri"},"position":{"line":$line,"character":$character}}}""")))
        process(r, server)
    end
end

# References
for doc in LanguageServer.getdocuments_value(server)
    uri = doc._uri
    print("References: $uri ")
    for loc in 1:sizeof(doc._content)-1
        mod(loc,100)==0 && println(loc/sizeof(doc._content))
        line, character = LanguageServer.get_position_at(doc, loc)
        r = parse(Request, (LanguageServer.JSON.parse("""{"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$uri"},"position":{"line":$line,"character":$character}}}""")))
        process(r, server)
    end
end

