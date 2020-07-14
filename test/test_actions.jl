server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true
server.jr_endpoint = nothing

LanguageServer.initialize_request(init_request, server, nothing)

testtext = """
decode_overlong
"""
LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("testdoc", "julia", 0, testtext)), server, nothing)

doc = LanguageServer.getdocument(server, LanguageServer.URI2("testdoc"))

@test !isempty(LanguageServer.textDocument_codeAction_request(LanguageServer.CodeActionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Range(LanguageServer.Position(0, 1), LanguageServer.Position(0, 1)), LanguageServer.CodeActionContext(LanguageServer.Diagnostic[doc.diagnostics[1]], missing)), server, nothing))

