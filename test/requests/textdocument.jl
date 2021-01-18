empty!(server._documents)

LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("none", "julia", 0, "")), server, server.jr_endpoint)
@test LanguageServer.hasdocument(server, LanguageServer.URI2("none"))

LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("none", "julia", 0, "")), server, server.jr_endpoint)
@test LanguageServer.hasdocument(server, LanguageServer.URI2("none"))

LanguageServer.textDocument_didSave_notification(LanguageServer.DidSaveTextDocumentParams(LanguageServer.TextDocumentIdentifier("none"), ""), server, server.jr_endpoint)

LanguageServer.textDocument_didChange_notification(LanguageServer.DidChangeTextDocumentParams(LanguageServer.VersionedTextDocumentIdentifier("none", 0), [LanguageServer.TextDocumentContentChangeEvent(missing, missing, "ran")]), server, server.jr_endpoint)


LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier("none")), server, server.jr_endpoint)
@test !LanguageServer.hasdocument(server, LanguageServer.URI2("none"))
