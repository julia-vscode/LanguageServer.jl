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

@testitem "formatting a file with a syntax error reports RequestFailed for both request kinds" setup=[TestSetup, SharedServer] begin
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
    # LSP 3.17 `RequestFailed`: understood, but cannot be carried out. The
    # message is shown to the user, so it must name the file and read as an
    # explanation rather than as an internal exception dump.
    @test result.code == LanguageServer.LSP_REQUEST_FAILED
    @test result.code == -32803
    @test occursin("code.jl", result.msg)
    @test !occursin("Failed to format document", result.msg)

    result = LanguageServer.textDocument_range_formatting_request(
        LanguageServer.DocumentRangeFormattingParams(
            LanguageServer.TextDocumentIdentifier(uri"file:///lsfmt/err/code.jl"),
            LanguageServer.Range(LanguageServer.Position(0, 0), LanguageServer.Position(0, 5)),
            LanguageServer.FormattingOptions(4, true, missing, missing, missing)),
        server, server.jr_endpoint)
    @test result isa LanguageServer.JSONRPC.JSONRPCError
    @test result.code == LanguageServer.LSP_REQUEST_FAILED
    @test occursin("code.jl", result.msg)
end

@testitem "formatting is only offered for Julia documents" begin
    import JSON

    # The formatter parses a whole document as Julia, so we must not claim to be
    # the formatting provider for Markdown / Julia-markdown: the editor picks a
    # single provider per document, so claiming it also suppresses the formatter
    # that could actually do the job.
    selector = LanguageServer.formatting_document_selector()
    languages = [f.language for f in selector]
    @test languages == ["julia"]
    @test !("markdown" in languages)
    @test !("juliamarkdown" in languages)

    # A client that can handle dynamic registration gets no static capability,
    # because a static one would apply to the client's whole document selector.
    dynamic = LanguageServer.ClientCapabilities(Dict("textDocument" => Dict(
        "formatting" => Dict("dynamicRegistration" => true),
        "rangeFormatting" => Dict("dynamicRegistration" => true))))
    caps = LanguageServer.ServerCapabilities(dynamic)
    @test caps.documentFormattingProvider === missing
    @test caps.documentRangeFormattingProvider === missing

    # ... and `missing` must be omitted from the wire, not serialised as null,
    # or the client still sees a formatting provider.
    wire = JSON.parse(JSON.json(caps))
    @test !haskey(wire, "documentFormattingProvider")
    @test !haskey(wire, "documentRangeFormattingProvider")

    # A client without dynamic registration keeps the previous behaviour rather
    # than losing formatting altogether.
    for client in (
        LanguageServer.ClientCapabilities(Dict("textDocument" => Dict(
            "formatting" => Dict("dynamicRegistration" => false)))),
        LanguageServer.ClientCapabilities(Dict{String,Any}()),
    )
        static_caps = LanguageServer.ServerCapabilities(client)
        @test static_caps.documentFormattingProvider === true
        @test static_caps.documentRangeFormattingProvider === true
    end

    # The two capabilities are decided independently.
    mixed = LanguageServer.ServerCapabilities(LanguageServer.ClientCapabilities(
        Dict("textDocument" => Dict(
            "formatting" => Dict("dynamicRegistration" => true),
            "rangeFormatting" => Dict("dynamicRegistration" => false)))))
    @test mixed.documentFormattingProvider === missing
    @test mixed.documentRangeFormattingProvider === true

    # The registration we send must carry the Julia-only selector.
    registration = LanguageServer.Registration(
        "id", "textDocument/formatting",
        LanguageServer.DocumentFormattingRegistrationOptions(selector, missing))
    wire = JSON.parse(JSON.json(LanguageServer.RegistrationParams([registration])))
    @test wire["registrations"][1]["method"] == "textDocument/formatting"
    @test wire["registrations"][1]["registerOptions"]["documentSelector"] ==
        [Dict("language" => "julia")]
end
