@testitem "formatting an excluded file is a no-op, not an error" setup=[TestSetup, SharedServer] begin
    import JuliaWorkspaces
    using LanguageServer.URIs2

    # A file excluded through its JuliaFormat.toml must produce an empty edit
    # list, not a JSONRPCError popup in the editor.
    JuliaWorkspaces.add_file!(server.workspace, JuliaWorkspaces.TextFile(
        uri"file:///lsfmt/JuliaFormat.toml",
        JuliaWorkspaces.SourceText("exclude = [\"gen/**\"]\n", "toml")))
    JuliaWorkspaces.add_file!(server.workspace, JuliaWorkspaces.TextFile(
        uri"file:///lsfmt/gen/code.jl",
        JuliaWorkspaces.SourceText("foo( 1,2 )\n", "julia")))

    result = LanguageServer.textDocument_formatting_request(
        LanguageServer.DocumentFormattingParams(
            LanguageServer.TextDocumentIdentifier(uri"file:///lsfmt/gen/code.jl"),
            LanguageServer.FormattingOptions(4, true, missing, missing, missing)),
        server, server.jr_endpoint)
    @test result == LanguageServer.TextEdit[]

    result = LanguageServer.textDocument_range_formatting_request(
        LanguageServer.DocumentRangeFormattingParams(
            LanguageServer.TextDocumentIdentifier(uri"file:///lsfmt/gen/code.jl"),
            LanguageServer.Range(LanguageServer.Position(0, 0), LanguageServer.Position(0, 5)),
            LanguageServer.FormattingOptions(4, true, missing, missing, missing)),
        server, server.jr_endpoint)
    @test result == LanguageServer.TextEdit[]

    # A sibling outside the excluded tree still formats.
    JuliaWorkspaces.add_file!(server.workspace, JuliaWorkspaces.TextFile(
        uri"file:///lsfmt/src/code.jl",
        JuliaWorkspaces.SourceText("foo( 1,2 )\n", "julia")))
    result = LanguageServer.textDocument_formatting_request(
        LanguageServer.DocumentFormattingParams(
            LanguageServer.TextDocumentIdentifier(uri"file:///lsfmt/src/code.jl"),
            LanguageServer.FormattingOptions(4, true, missing, missing, missing)),
        server, server.jr_endpoint)
    @test result isa Vector{LanguageServer.TextEdit}
    @test !isempty(result)
end

@testitem "formatting a file with a syntax error reports -32000 for both request kinds" setup=[TestSetup, SharedServer] begin
    import JuliaWorkspaces
    using LanguageServer.URIs2

    JuliaWorkspaces.add_file!(server.workspace, JuliaWorkspaces.TextFile(
        uri"file:///lsfmt/err/code.jl",
        JuliaWorkspaces.SourceText("function foo( end\n", "julia")))

    result = LanguageServer.textDocument_formatting_request(
        LanguageServer.DocumentFormattingParams(
            LanguageServer.TextDocumentIdentifier(uri"file:///lsfmt/err/code.jl"),
            LanguageServer.FormattingOptions(4, true, missing, missing, missing)),
        server, server.jr_endpoint)
    @test result isa LanguageServer.JSONRPC.JSONRPCError
    @test result.code == -32000

    result = LanguageServer.textDocument_range_formatting_request(
        LanguageServer.DocumentRangeFormattingParams(
            LanguageServer.TextDocumentIdentifier(uri"file:///lsfmt/err/code.jl"),
            LanguageServer.Range(LanguageServer.Position(0, 0), LanguageServer.Position(0, 5)),
            LanguageServer.FormattingOptions(4, true, missing, missing, missing)),
        server, server.jr_endpoint)
    @test result isa LanguageServer.JSONRPC.JSONRPCError
    @test result.code == -32000
end
