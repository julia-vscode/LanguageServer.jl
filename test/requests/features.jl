sig_test(line, char) = LanguageServer.textDocument_signatureHelp_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)

def_test(line, char) = LanguageServer.textDocument_definition_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)

ref_test(line, char) = LanguageServer.textDocument_references_request(LanguageServer.ReferenceParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing, missing, LanguageServer.ReferenceContext(true)), server, server.jr_endpoint)

rename_test(line, char) = LanguageServer.textDocument_rename_request(LanguageServer.RenameParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Position(line, char), missing, "newname"), server, server.jr_endpoint)


@testset "signatures" begin
    doc = settestdoc("""
    rand()
    Base.rand()
    func(arg) = 1
    func()
    struct T
        a
        b
    end
    T()
    struct S{R}
        a
        S() = new(1)
    end
    using Base:argtail
    argtail()
    S{R}()
    """)
    @test !isempty(sig_test(0, 5).signatures)
    @test !isempty(sig_test(1, 10).signatures)
    @test !isempty(sig_test(3, 5).signatures)
    @test !isempty(sig_test(8, 2).signatures)
    @test_broken !isempty(sig_test(15, 5).signatures)

    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[3].meta.binding, doc.cst.meta.scope, sigs, LanguageServer.getenv(server))
        @test length(sigs) == 1
    end
    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[5].meta.binding, doc.cst.meta.scope, sigs, LanguageServer.getenv(server))
        @test length(sigs) == 1
    end
    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[1][1].meta.ref, doc.cst.meta.scope, sigs, LanguageServer.getenv(server))
        @test length(sigs) > 0
    end
    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[7].meta.binding, doc.cst.meta.scope, sigs, LanguageServer.getenv(server))
        @test length(sigs) == 1
    end
    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[9][1].meta.ref, doc.cst.meta.scope, sigs, LanguageServer.getenv(server))
        @test length(sigs) == 1
    end
end

@testset "definitions" begin
    settestdoc("""
    rand()
    func(arg) = 1
    func()
    Float64
    """)
    # @test !isempty(def_test(0, 3))
    @test !isempty(def_test(2, 3))
    @test !isempty(def_test(3, 3))
end

@testset "references" begin
    settestdoc("""
    func(arg) = 1
    func()
    """)
    @test length(ref_test(1, 2)) == 2
end

@testset "rename" begin
    settestdoc("""
    func(arg) = 1
    func()
    """)
    @test length(rename_test(0, 2).documentChanges[1].edits) == 2
end

@testset "get_file_loc" begin
    doc = settestdoc("""
    func(arg) = 1
    func()
    """)
    @test LanguageServer.get_file_loc(doc.cst.args[2].args[1]) == (doc, 14)
end

@testset "doc symbols" begin
    doc = settestdoc("""
    a = 1
    b = 2
    function func() end
    function (::Bar)() end
    function (::Type{Foo})() end
    """)
    @test all(item.name in ("a", "b", "func", "::Bar", "::Type{Foo}") for item in LanguageServer.textDocument_documentSymbol_request(LanguageServer.DocumentSymbolParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), missing, missing), server, server.jr_endpoint))
end

@testset "inlay hints" begin
    doc = settestdoc("""
    a = 1
    b = 2.0
    f(xx) = xx
    f(xxx, yyy) = xx + yy
    f(2)
    f(2, 3)
    f(2, f(3))

    f(2, 3) # this request is outside of the requested range
    """)
    function hints_with_mode(mode)
        old_mode = server.inlay_hint_mode
        server.inlay_hint_mode = mode
        hints = LanguageServer.textDocument_inlayHint_request(
            LanguageServer.InlayHintParams(
                LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"),
                LanguageServer.Range(LanguageServer.Position(0, 0), LanguageServer.Position(7, 0)),
                missing
            ),
            server,
            server.jr_endpoint
        )
        server.inlay_hint_mode = old_mode
        return hints
    end
    @test hints_with_mode(:none) === nothing
    @test map(x -> x.label, hints_with_mode(:literals)) == [
        string("::", Int),
        "::Float64",
        "xx:",
        "xxx:",
        "yyy:",
        "xxx:",
        "xx:"
    ]
    @test map(x -> x.label, hints_with_mode(:all)) == [
        string("::", Int),
        "::Float64",
        "xx:",
        "xxx:",
        "yyy:",
        "xxx:",
        "yyy:", # not a literal
        "xx:"
    ]
    map(x -> x.position, hints_with_mode(:all)) == [
        LanguageServer.Position(0, 1),
        LanguageServer.Position(1, 1),
        LanguageServer.Position(2, 4),
        LanguageServer.Position(4, 2),
        LanguageServer.Position(5, 2),
        LanguageServer.Position(5, 5),
        LanguageServer.Position(6, 2),
        LanguageServer.Position(6, 5),
        LanguageServer.Position(6, 7),
    ]
end
