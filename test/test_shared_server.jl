import Pkg
using LanguageServer.URIs2
using LanguageServer: LanguageServerInstance

include("test_shared_init_request.jl")

function settestdoc(text)
    empty!(server._documents)
    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri"untitled:testdoc", "julia", 0, text)), server, nothing)

    doc = LanguageServer.getdocument(server, uri"untitled:testdoc")
    LanguageServer.parse_all(doc, server)
    doc
end

function closetestdoc()
    LanguageServer.textDocument_didClose_notification(LanguageServer.DidCloseTextDocumentParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc")), server, nothing)
end

completion_test(line, char) = LanguageServer.textDocument_completion_request(LanguageServer.CompletionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing), server, server.jr_endpoint)
action_request_test(line0, char0, line1=line0, char1=char0; diags=[]) = LanguageServer.textDocument_codeAction_request(LanguageServer.CodeActionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Range(LanguageServer.Position(line0, char0), LanguageServer.Position(line1, char1)), LanguageServer.CodeActionContext(diags, missing)), server, server.jr_endpoint)
sig_test(line, char) = LanguageServer.textDocument_signatureHelp_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)
def_test(line, char) = LanguageServer.textDocument_definition_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)
ref_test(line, char) = LanguageServer.textDocument_references_request(LanguageServer.ReferenceParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing, missing, LanguageServer.ReferenceContext(true)), server, server.jr_endpoint)
rename_test(line, char) = LanguageServer.textDocument_rename_request(LanguageServer.RenameParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing, "newname"), server, server.jr_endpoint)
hover_test(line, char) = LanguageServer.textDocument_hover_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)
range_formatting_test(line0, char0, line1, char1) = LanguageServer.textDocument_range_formatting_request(LanguageServer.DocumentRangeFormattingParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Range(LanguageServer.Position(line0, char0), LanguageServer.Position(line1, char1)), LanguageServer.FormattingOptions(4, true, missing, missing, missing)), server, server.jr_endpoint)

# TODO Replace this with a proper mock endpoint
JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true
server.jr_endpoint = nothing
LanguageServer.initialize_request(init_request, server, nothing)
