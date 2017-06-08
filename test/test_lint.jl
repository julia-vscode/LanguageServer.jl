server = LanguageServerInstance(IOBuffer(), IOBuffer(), true)

function ≂(r1::LanguageServer.Range, r2::LanguageServer.Range)
    r1.start.line == r2.start.line &&
    r1.start.character == r2.start.character &&
    r1.stop.line == r2.stop.line &&
    r1.stop.character == r2.stop.character
end


@testset "undeclared variable" begin 
    server.documents["none"] = doc = LanguageServer.Document("none","variable",true)
    LanguageServer.parse_all(doc, server)

    d = doc.diagnostics[1]
    @test d.loc == 0:8
    vscode_diag = LanguageServer.convert_diagnostic(d, doc)
    @test vscode_diag.range ≂ Range(0, 0, 0, 8)
end


@testset "missing ws on op" begin 
    server.documents["none"] = doc = LanguageServer.Document("none","1+2",true)
    LanguageServer.parse_all(doc, server)

    d = doc.diagnostics[1]
    @test d.loc == 1:2
    vscode_diag = LanguageServer.convert_diagnostic(d, doc)
    @test vscode_diag.range ≂ Range(0, 1, 0, 2)
end

@testset "extra ws on op" begin 
    server.documents["none"] = doc = LanguageServer.Document("none","1 : 2",true)
    LanguageServer.parse_all(doc, server)

    d = doc.diagnostics[1]
    @test d.loc == 2:3
    vscode_diag = LanguageServer.convert_diagnostic(d, doc)
    @test vscode_diag.range ≂ Range(0, 2, 0, 3)
end

@testset "missing ws on comma" begin 
    doc = LanguageServer.Document("none","1,2",true)
    LanguageServer.parse_all(doc, server)

    d = doc.diagnostics[1]
    @test d.loc == 1:2
    vscode_diag = LanguageServer.convert_diagnostic(d, doc)
    @test vscode_diag.range ≂ Range(0, 1, 0, 2)
end

@testset "extra ws on comma" begin 
    doc = LanguageServer.Document("none","1 , 2",true)
    LanguageServer.parse_all(doc, server)

    d = doc.diagnostics[1]
    @test d.loc == 2:3
    vscode_diag = LanguageServer.convert_diagnostic(d, doc)
    @test vscode_diag.range ≂ Range(0, 2, 0, 3)
end

@testset "extra ws on brackets" begin 
    doc = LanguageServer.Document("none","( 1 )",true)
    LanguageServer.parse_all(doc, server)

    d = doc.diagnostics[1]
    @test d.loc == 0:1
    vscode_diag = LanguageServer.convert_diagnostic(d, doc)
    @test vscode_diag.range ≂ Range(0, 0, 0, 1)

    d = doc.diagnostics[2]
    @test d.loc == 4:5
    vscode_diag = LanguageServer.convert_diagnostic(d, doc)
    @test vscode_diag.range ≂ Range(0, 4, 0, 5)
end

@testset "deprecated type syntaxes" begin 
    server.documents["none"] = doc = LanguageServer.Document("none","""
    abstract T
    type T end
    immutable T end
    typealias T T
    bitstype T 8
    """,true)
    LanguageServer.parse_all(doc, server)

    d = doc.diagnostics[1]
    @test d.loc == 0:8
    @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(0, 0, 0, 8)

    d = doc.diagnostics[2]
    @test d.loc == 11:15
    @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(1, 0, 1, 4)
    
    d = doc.diagnostics[3]
    @test d.loc == 22:31
    @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(2, 0, 2, 9)
    
    d = doc.diagnostics[4]
    @test d.loc == 38:47
    @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(3, 0, 3, 9)

    d = doc.diagnostics[5]
    @test d.loc == 52:60
    @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(4, 0, 4, 8)
end
