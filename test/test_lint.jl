server = LanguageServerInstance(IOBuffer(), IOBuffer(), true)
server.runlinter = true
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

# 
# @testset "missing ws on op" begin 
#     server.documents["none"] = doc = LanguageServer.Document("none","1+2",true)
#     LanguageServer.parse_all(doc, server)

#     d = doc.diagnostics[1]
#     @test d.loc == 1:2
#     vscode_diag = LanguageServer.convert_diagnostic(d, doc)
#     @test vscode_diag.range ≂ Range(0, 1, 0, 2)
# end

# @testset "extra ws on op" begin 
#     server.documents["none"] = doc = LanguageServer.Document("none","1 : 2",true)
#     LanguageServer.parse_all(doc, server)

#     d = doc.diagnostics[1]
#     @test d.loc == 2:3
#     vscode_diag = LanguageServer.convert_diagnostic(d, doc)
#     @test vscode_diag.range ≂ Range(0, 2, 0, 3)
# end

# @testset "missing ws on comma" begin 
#     doc = LanguageServer.Document("none","1,2",true)
#     LanguageServer.parse_all(doc, server)

#     d = doc.diagnostics[1]
#     @test d.loc == 1:2
#     vscode_diag = LanguageServer.convert_diagnostic(d, doc)
#     @test vscode_diag.range ≂ Range(0, 1, 0, 2)
# end

# @testset "extra ws on comma" begin 
#     doc = LanguageServer.Document("none","1 , 2",true)
#     LanguageServer.parse_all(doc, server)

#     d = doc.diagnostics[1]
#     @test d.loc == 2:3
#     vscode_diag = LanguageServer.convert_diagnostic(d, doc)
#     @test vscode_diag.range ≂ Range(0, 2, 0, 3)
# end

# @testset "extra ws on brackets" begin 
#     doc = LanguageServer.Document("none","( 1 )",true)
#     LanguageServer.parse_all(doc, server)

#     d = doc.diagnostics[1]
#     @test d.loc == 0:1
#     vscode_diag = LanguageServer.convert_diagnostic(d, doc)
#     @test vscode_diag.range ≂ Range(0, 0, 0, 1)

#     d = doc.diagnostics[2]
#     @test d.loc == 4:5
#     vscode_diag = LanguageServer.convert_diagnostic(d, doc)
#     @test vscode_diag.range ≂ Range(0, 4, 0, 5)
# end

@testset "deprecated type syntaxes" begin 
    @testset "abstract" begin
        server.documents["none"] = doc = LanguageServer.Document("none","""
        abstract T
        """,true)
        LanguageServer.parse_all(doc, server)

        d = doc.diagnostics[1]
        @test d.loc == 0:8
        @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(0, 0, 0, 8)
    end

    @testset "type" begin
        server.documents["none"] = doc = LanguageServer.Document("none","""
        type T end
        """,true)
        LanguageServer.parse_all(doc, server)

        d = doc.diagnostics[1]
        @test d.loc == 0:4
        @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(0, 0, 0, 4)
    end

    @testset "immutable" begin
        server.documents["none"] = doc = LanguageServer.Document("none","""
        immutable T end
        """,true)
        LanguageServer.parse_all(doc, server)

        d = doc.diagnostics[1]
        @test d.loc == 0:9
        @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(0, 0, 0, 9)
    end

    @testset "typealias" begin
        server.documents["none"] = doc = LanguageServer.Document("none","""
        immutable T end
        """,true)
        LanguageServer.parse_all(doc, server)

        d = doc.diagnostics[1]
        @test d.loc == 0:9
        @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(0, 0, 0, 9)
    end

    @testset "bitstype" begin
        server.documents["none"] = doc = LanguageServer.Document("none","""
        bitstype a b
        """,true)
        LanguageServer.parse_all(doc, server)

        d = doc.diagnostics[1]
        @test d.loc == 0:8
        @test LanguageServer.convert_diagnostic(d, doc).range ≂ Range(0, 0, 0, 8)
    end
end
