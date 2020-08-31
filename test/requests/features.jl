sig_test(line, char) = LanguageServer.textDocument_signatureHelp_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)

def_test(line, char) = LanguageServer.textDocument_definition_request(LanguageServer.TextDocumentPositionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(line, char)), server, server.jr_endpoint)

ref_test(line, char) = LanguageServer.textDocument_references_request(LanguageServer.ReferenceParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(line, char), missing, missing, LanguageServer.ReferenceContext(true)), server, server.jr_endpoint)

rename_test(line, char) = LanguageServer.textDocument_rename_request(LanguageServer.RenameParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Position(line, char), missing, "newname"), server, server.jr_endpoint)


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
    """)
    @test !isempty(sig_test(0, 5).signatures)
    @test !isempty(sig_test(1, 10).signatures)
    @test !isempty(sig_test(3, 5).signatures)
    @test !isempty(sig_test(8, 2).signatures)

    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[3].meta.binding, doc.cst.meta.scope, sigs, server)
        @test length(sigs) == 1
    end
    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[5].meta.binding, doc.cst.meta.scope, sigs, server)
        @test length(sigs) == 1
    end
    let sigs = LanguageServer.SignatureInformation[]
        LanguageServer.get_signatures(doc.cst[1][1].meta.ref, doc.cst.meta.scope, sigs, server)
        @test length(sigs) > 0
    end
end

@testset "definitions" begin
    settestdoc("""
    rand()
    func(arg) = 1
    func()
    """)
    # @test !isempty(def_test(0, 3))
    @test !isempty(def_test(2, 3))
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
    """)
    @test all(item.name in ("a", "b", "func") for item in LanguageServer.textDocument_documentSymbol_request(LanguageServer.DocumentSymbolParams(LanguageServer.TextDocumentIdentifier("testdoc"), missing, missing), server, server.jr_endpoint))
end