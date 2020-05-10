server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true

LanguageServer.process(LanguageServer.parse(LanguageServer.JSONRPC.Request, Dict("jsonrpc"=>"2.0","id"=>0,"method"=>"initialize","params"=>init_request)), server)

testtext = """
decode_overlong
"""
LanguageServer.process(LanguageServer.JSONRPC.Request{Val{Symbol("textDocument/didOpen")},LanguageServer.DidOpenTextDocumentParams}(0, LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("testdoc", "julia", 0, testtext))), server)

doc = LanguageServer.getdocument(server, LanguageServer.URI2("testdoc"))

@test !isempty(LanguageServer.process(LanguageServer.JSONRPC.Request{Val{Symbol("textDocument/codeAction")},LanguageServer.CodeActionParams}(0, LanguageServer.CodeActionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Range(LanguageServer.Position(0,1),LanguageServer.Position(0,1)), LanguageServer.CodeActionContext(LanguageServer.Diagnostic[doc.diagnostics[1]], missing))), server))

