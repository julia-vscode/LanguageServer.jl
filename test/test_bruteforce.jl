@testitem "brute force tests" setup=[TestSetup, SharedServer] begin
    using JuliaWorkspaces

    @info "Self-parse test"
    if get(ENV, "CI", false) != false
        @info "skipping brute-force tests on CI"
    else
        # Load the LanguageServer source folder into the workspace.
        srcdir = dirname(String(first(methods(LanguageServer.eval)).file))
        folder_uri = LanguageServer.filepath2uri(srcdir)
        for f in JuliaWorkspaces.read_path_into_textdocuments(folder_uri, ignore_io_errors=true)
            if !haskey(server._files_from_disc, f.uri)
                server._files_from_disc[f.uri] = f
                JuliaWorkspaces.add_file!(server.workspace, f)
            end
        end

        # run tests against each position in each document
        for uri in JuliaWorkspaces.get_text_files(server.workspace)
            st = LanguageServer.jw_source_text(server, uri)
            text = st.content
            @info "Testing LS functionality at all offsets" file=uri
            offsets = push!([i - 1 for i in eachindex(text)], sizeof(text))
            for offset in offsets
                tdi = LanguageServer.TextDocumentIdentifier(uri)
                pos = LanguageServer.Position(LanguageServer.get_position_from_offset(st, offset)...)
                @test LanguageServer.get_offset(st, LanguageServer.get_position_from_offset(st, offset)...) == offset
                LanguageServer.textDocument_completion_request(LanguageServer.CompletionParams(tdi, pos, missing), server, server.jr_endpoint)
                LanguageServer.textDocument_hover_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                LanguageServer.textDocument_signatureHelp_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                LanguageServer.textDocument_definition_request(LanguageServer.TextDocumentPositionParams(tdi, pos), server, server.jr_endpoint)
                LanguageServer.textDocument_references_request(LanguageServer.ReferenceParams(tdi, pos, missing, missing, LanguageServer.ReferenceContext(true)), server, server.jr_endpoint)
                LanguageServer.textDocument_rename_request(LanguageServer.RenameParams(tdi, pos, missing, "newname"), server, server.jr_endpoint)
            end
        end

        for uri in JuliaWorkspaces.get_text_files(server.workspace)
            symbols = length(LanguageServer.textDocument_documentSymbol_request(LanguageServer.DocumentSymbolParams(LanguageServer.TextDocumentIdentifier(uri), missing, missing), server, server.jr_endpoint))
            @info "Found $symbols symbols" file=uri
        end

        LanguageServer.workspace_symbol_request(LanguageServer.WorkspaceSymbolParams("", missing, missing), server, server.jr_endpoint)
    end
end
