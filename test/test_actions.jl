server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true

LanguageServer.initialize_request(nothing, init_request, server)

testtext = """
decode_overlong
"""
LanguageServer.textDocument_didOpen_notification(nothing, LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("testdoc", "julia", 0, testtext)), server)

doc = LanguageServer.getdocument(server, LanguageServer.URI2("testdoc"))

@test !isempty(LanguageServer.textDocument_codeAction_request(nothing, LanguageServer.CodeActionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Range(LanguageServer.Position(0,1),LanguageServer.Position(0,1)), LanguageServer.CodeActionContext(LanguageServer.Diagnostic[doc.diagnostics[1]], missing)), server))

