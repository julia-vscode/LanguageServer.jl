## Testing as in test/runtests.jl and test/requests/completions.jl
using Test, Sockets, LanguageServer, CSTParser, SymbolServer, SymbolServer.Pkg, StaticLint, LanguageServer.JSON, LanguageServer.JSONRPC
using LanguageServer: Document, get_text, get_offset, get_line_offsets, get_position_at, get_open_in_editor, set_open_in_editor, is_workspace_file, applytextdocumentchanges

init_request = LanguageServer.InitializeParams(
    9902,
    missing,
    nothing,
    nothing,
    missing,
    LanguageServer.ClientCapabilities(
        LanguageServer.WorkspaceClientCapabilities(
            true,
            LanguageServer.WorkspaceEditClientCapabilities(true, missing, missing),
            LanguageServer.DidChangeConfigurationClientCapabilities(false),
            LanguageServer.DidChangeWatchedFilesClientCapabilities(false,),
            LanguageServer.WorkspaceSymbolClientCapabilities(true, missing),
            LanguageServer.ExecuteCommandClientCapabilities(true),
            missing,
            missing
        ),
        LanguageServer.TextDocumentClientCapabilities(
            LanguageServer.TextDocumentSyncClientCapabilities(true, true, true, true),
            LanguageServer.CompletionClientCapabilities(true, LanguageServer.CompletionItemClientCapabilities(true, missing, missing, missing, missing, missing), missing, missing),
            LanguageServer.HoverClientCapabilities(true, missing),
            LanguageServer.SignatureHelpClientCapabilities(true, missing, missing),
            LanguageServer.DeclarationClientCapabilities(false, missing),
            missing, # DefinitionClientCapabilities(),
            missing, # TypeDefinitionClientCapabilities(),
            missing, # ImplementationClientCapabilities(),
            missing, # ReferenceClientCapabilities(),
            LanguageServer.DocumentHighlightClientCapabilities(true),
            LanguageServer.DocumentSymbolClientCapabilities(true, missing, missing),
            LanguageServer.CodeActionClientCapabilities(true, missing, missing),
            LanguageServer.CodeLensClientCapabilities(true),
            missing, # DocumentLinkClientCapabilities(),
            missing, # DocumentColorClientCapabilities(),
            LanguageServer.DocumentFormattingClientCapabilities(true),
            missing, # DocumentRangeFormattingClientCapabilities(),
            missing, # DocumentOnTypeFormattingClientCapabilities(),
            LanguageServer.RenameClientCapabilities(true, true),
            missing, # PublishDiagnosticsClientCapabilities(),
            missing, # FoldingRangeClientCapabilities(),
            missing, # SelectionRangeClientCapabilities()
        ),
        missing,
        missing
    ),
    "off",
    missing,
    missing
)

server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true
server.jr_endpoint = nothing
LanguageServer.initialize_request(init_request, server, nothing)

JSONRPC.send(::Nothing, ::Any, ::Any) = nothing
function settestdoc(text)
    empty!(server._documents)
    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("testdoc", "julia", 0, text)), server, nothing)

    doc = LanguageServer.getdocument(server, LanguageServer.URI2("testdoc"))
    LanguageServer.parse_all(doc, server)
    doc
end

completion_test(line, char) = LanguageServer.textDocument_completion_request(LanguageServer.CompletionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(line, char), missing), server, server.jr_endpoint)


## A completion that is working
settestdoc("import Base: r")
labels = [item.label for item in completion_test(0, 14).items]

## Another completion
settestdoc("using ")
labels = [item.label for item in completion_test(0, 6).items]

## Another completion
settestdoc("me")
labels = [item.label for item in completion_test(0, 2).items]

## Another completion
settestdoc("""phi = 1
    (phi,""")
labels = [item.label for item in completion_test(0, 13).items]
println(labels)

## Another completion
doctext = """
struct Foo
    bar
    baz
end

phi = Foo(1, 2)
(phi,"""
settestdoc(doctext)
labels = [item.label for item in completion_test(0, length(doctext)).items]
println(labels)

## Another completion
doctext = """
struct Foo
    bar
    baz
end

function do_something(x::Foo)
    x
end

phi = Foo(1, 2)
(phi,"""
settestdoc(doctext)
labels = [item.label for item in completion_test(0, length(doctext)).items]
println(labels)
