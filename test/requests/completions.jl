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
    ^\\therefor
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

    @test completion_test(5, 10).items[1].textEdit.newText == "∴"
    @test completion_test(5, 10).items[1].textEdit.range == LanguageServer.Range(5, 1, 5, 10)
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

@testset "getfield completions" begin
    settestdoc("Base.")
    @test any(item.label == "rand" for item in completion_test(0, 5).items)

    settestdoc("Base.r")
    @test any(item.label == "rand" for item in completion_test(0, 6).items)

    settestdoc("""
    using Base.Meta
    Base.Meta.
    """)
    @test any(item.label == "quot" for item in completion_test(1, 10).items)

    settestdoc("""
    module M 
    inner = 1
    end
    M.
    """)
    @test any(item.label == "inner" for item in completion_test(3, 2).items)

    settestdoc("""
    x = Expr()
    x.
    """)
    @test all(item.label in ("head", "args") for item in completion_test(1, 2).items)

    settestdoc("""
    struct T
        f1
        f2
    end
    x = T()
    x.
    """)
    @test all(item.label in ("f1", "f2") for item in completion_test(1, 2).items)
end



@testset "token completions" begin
    settestdoc("B")
    @test any(item.label == "Base" for item in completion_test(0, 1).items)

    settestdoc("r")
    @test any(item.label == "rand" for item in completion_test(0, 1).items)

    settestdoc("@t")
    @test any(item.label == "@time" for item in completion_test(0, 2).items)
    
    settestdoc("i")
    @test any(item.label == "if" for item in completion_test(0, 1).items)
    
    settestdoc("i")
    @test any(item.label == "in" for item in completion_test(0, 1).items)
    
    settestdoc("for")
    @test any(item.label == "for" for item in completion_test(0, 3).items)

    settestdoc("in")
    @test any(item.label == "in" for item in completion_test(0, 2).items)
    
    settestdoc("isa")
    @test any(item.label == "isa" for item in completion_test(0, 3).items)
end

@testset "scope var completions" begin
    settestdoc("""myvar = 1
    myv""")
    @test any(item.label == "myvar" for item in completion_test(1, 3).items)
end
