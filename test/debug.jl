using LanguageServer, SymbolServer
using LanguageServer: process, JSONRPC.Request

function start_server(path = "")
    server = LanguageServerInstance(IOBuffer(), IOBuffer(), true, "", "")
    @async run(server)

    initstr = """{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"processId":0,"rootPath":null,"rootUri":"$path","capabilities":{"workspace":{"applyEdit":true,"workspaceEdit":{"documentChanges":true},"didChangeConfiguration":{"dynamicRegistration":true},"didChangeWatchedFiles":{"dynamicRegistration":true},"symbol":{"dynamicRegistration":true,"symbolKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]}},"executeCommand":{"dynamicRegistration":true},"configuration":true,"workspaceFolders":true},"textDocument":{"publishDiagnostics":{"relatedInformation":true},"synchronization":{"dynamicRegistration":true,"willSave":true,"willSaveWaitUntil":true,"didSave":true},"completion":{"dynamicRegistration":true,"contextSupport":true,"completionItem":{"snippetSupport":true,"commitCharactersSupport":true,"documentationFormat":["markdown","plaintext"],"deprecatedSupport":true},"completionItemKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]}},"hover":{"dynamicRegistration":true,"contentFormat":["markdown","plaintext"]},"signatureHelp":{"dynamicRegistration":true,"signatureInformation":{"documentationFormat":["markdown","plaintext"]}},"definition":{"dynamicRegistration":true},"references":{"dynamicRegistration":true},"documentHighlight":{"dynamicRegistration":true},"documentSymbol":{"dynamicRegistration":true,"symbolKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]}},"codeAction":{"dynamicRegistration":true,"codeActionLiteralSupport":{"codeActionKind":{"valueSet":["","quickfix","refactor","refactor.extract","refactor.inline","refactor.rewrite","source","source.organizeImports"]}}},"codeLens":{"dynamicRegistration":true},"formatting":{"dynamicRegistration":true},"rangeFormatting":{"dynamicRegistration":true},"onTypeFormatting":{"dynamicRegistration":true},"rename":{"dynamicRegistration":true},"documentLink":{"dynamicRegistration":true},"typeDefinition":{"dynamicRegistration":true},"implementation":{"dynamicRegistration":true},"colorProvider":{"dynamicRegistration":true}}},"trace":"off","workspaceFolders":[]}}"""
    process(parse(Request, LanguageServer.JSON.parse(initstr)), server)
    process(Request{Val{Symbol("initialized")},Any}(0, nothing), server)
    return server
end

function load_file(text, server)
    process(Request{Val{Symbol("textDocument/didOpen")},LanguageServer.DidOpenTextDocumentParams}(0, LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("none", "julia", 0, text))), server)
    doc = server.documents[LanguageServer.URI2("none")]
end

function hover(text, line, col, server)
    doc = load_file(text, server)
    r = Request{Val{Symbol("textDocument/hover")},LanguageServer.TextDocumentPositionParams}(0, LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("none"), LanguageServer.Position(line, col)))
    process(r, server)
end

function completion(text, line, col, server)
    doc = load_file(text, server)
    r = Request{Val{Symbol("textDocument/completion")},LanguageServer.CompletionParams}(0, LanguageServer.CompletionParams(LanguageServer.TextDocumentIdentifier("none"), LanguageServer.Position(line, col), nothing))
    process(r, server)
end

function definition(text, line, col, server)
    doc = load_file(text, server)
    r = Request{Val{Symbol("textDocument/definition")},LanguageServer.TextDocumentPositionParams}(0, LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("none"), LanguageServer.Position(line, col)))
    process(r, server)
end
