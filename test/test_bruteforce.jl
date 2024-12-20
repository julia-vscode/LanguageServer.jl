@testitem "brute force tests" begin
    using LanguageServer: get_text, get_uri
    include("test_shared_server.jl")

    function on_all_docs(server, f)
        for doc in values(server._documents)
            f(doc)
        end
    end

    function on_all_offsets(doc, f)
        offset = 1
        while offset <= lastindex(get_text(doc))
            f(doc, offset)
            offset = nextind(get_text(doc), offset)
        end
    end

    @info "Self-parse test"
    if get(ENV, "CI", false) != false
        @info "skipping brute-force tests on CI"
    else
        # run tests against each position in each document
        empty!(server._documents)
        LanguageServer.load_folder(dirname(String(first(methods(LanguageServer.eval)).file)), server)
        on_all_docs(server, doc -> begin
            @info "Testing LS functionality at all offsets" file = get_uri(doc)
            on_all_offsets(doc, function (doc, offset)
                tdi = LanguageServer.TextDocumentIdentifier(get_uri(doc))
                pos = LanguageServer.Position(LanguageServer.get_position_from_offset(doc, offset)...)
                @test LanguageServer.get_offset(doc, LanguageServer.get_position_from_offset(doc, offset)...) == offset
                LanguageServer.textDocument_completion_request(LanguageServer.CompletionParams(tdi, pos, missing), server, server.jr_endpoint)
                LanguageServer.textDocument_hover_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                LanguageServer.textDocument_signatureHelp_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                LanguageServer.textDocument_definition_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                LanguageServer.textDocument_references_request(LanguageServer.ReferenceParams(tdi, pos, missing, missing, LanguageServer.ReferenceContext(true)), server, server.jr_endpoint)
                LanguageServer.textDocument_rename_request(LanguageServer.RenameParams(tdi, pos, missing, "newname"), server, server.jr_endpoint)
            end)
        end)

        on_all_docs(server, doc -> begin
            symbols = length(LanguageServer.textDocument_documentSymbol_request(LanguageServer.DocumentSymbolParams(LanguageServer.TextDocumentIdentifier(get_uri(doc)), missing, missing), server, server.jr_endpoint))
            @info "Found $symbols symbols" file = get_uri(doc)
        end)

        LanguageServer.workspace_symbol_request(LanguageServer.WorkspaceSymbolParams("", missing, missing), server, server.jr_endpoint)
    end
end
