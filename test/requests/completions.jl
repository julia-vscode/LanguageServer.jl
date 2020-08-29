server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))
server.runlinter = true
server.jr_endpoint = nothing
LanguageServer.initialize_request(init_request, server, nothing)

function settestdoc(text)
    empty!(server._documents)
    LanguageServer.textDocument_didOpen_notification(LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("testdoc", "julia", 0, text)), server, nothing)

    doc = LanguageServer.getdocument(server, LanguageServer.URI2("testdoc"))
    LanguageServer.parse_all(doc, server)
end

completion_test(line, char) = LanguageServer.textDocument_completion_request(LanguageServer.CompletionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(line, char), missing), server, server.jr_endpoint)


@testset "latex completions" begin
    settestdoc("""
    \\therefor
    .\\therefor
    #\\therefor
    "\\therefor"
    \"\"\"\\therefor\"\"\"
    """)
    @test completion_test(0, 9).items[1].textEdit.newText == "∴"
    @test completion_test(0, 9).items[1].textEdit.range == LanguageServer.Range(0, 0, 0, 9)
    
    @test completion_test(1, 10).items[1].textEdit.newText == "∴"
    @test completion_test(1, 10).items[1].textEdit.range == LanguageServer.Range(1, 1, 1, 10)
    
    @test completion_test(2, 10).items[1].textEdit.newText == "∴"
    @test completion_test(2, 10).items[1].textEdit.range == LanguageServer.Range(2, 1, 2, 10)
    
    @test completion_test(3, 10).items[1].textEdit.newText == "∴"
    @test completion_test(3, 10).items[1].textEdit.range == LanguageServer.Range(3, 1, 3, 10)
    
    @test completion_test(4, 12).items[1].textEdit.newText == "∴"
    @test completion_test(4, 12).items[1].textEdit.range == LanguageServer.Range(4, 3, 4, 12)
end

@testset "path completions" begin
end

@testset "import completions" begin
    settestdoc("import Base: r")
    @test any(item.label == "rand" for item in completion_test(0, 14).items)

    settestdoc("import ")
    @test all(item.label in ("Main", "Base", "Core") for item in completion_test(0, 7).items)
    
    settestdoc("""module M end
    import .""")
    @test_broken completion_test(1, 8).items[1].label == "M"

    settestdoc("import Base.")
    @test any(item.label == "Meta" for item in completion_test(0, 12).items)

    settestdoc("import Base.M")
    @test any(item.label == "Meta" for item in completion_test(0, 13).items)

    settestdoc("import Bas")
    @test any(item.label == "Base" for item in completion_test(0, 10).items)
end
