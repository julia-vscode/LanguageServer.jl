@setup_workload begin
    workload_text = """
    module PrecompileWorkload

    const GREETING = "hello"

    struct Point
        x::Float64
        y::Float64
    end

    function distance(a::Point, b::Point)
        dx = a.x - b.x
        dy = a.y - b.y
        return sqrt(dx^2 + dy^2)
    end

    end
    """

    @compile_workload begin
        # Drive the hot request paths against an in-memory DynamicOff
        # workspace: no child processes and no background tasks (which are
        # not allowed during precompile).
        mktempdir() do store_path
            server = LanguageServerInstance(IOBuffer(), IOBuffer(), "")
            server.jr_endpoint = NullEndpoint()
            server.status = :running
            server.workspace = JuliaWorkspaces.JuliaWorkspace(
                dynamic=JuliaWorkspaces.DynamicOff, store_path=store_path)

            uri = URI("untitled:precompile_workload.jl")
            textDocument_didOpen_notification(
                DidOpenTextDocumentParams(TextDocumentItem(uri, "julia", 0, workload_text)),
                server, nothing)

            textDocument_didChange_notification(
                DidChangeTextDocumentParams(
                    VersionedTextDocumentIdentifier(uri, 1),
                    [TextDocumentContentChangeEvent(missing, missing, workload_text)]),
                server, nothing)

            doc_id = TextDocumentIdentifier(uri)
            textDocument_completion_request(CompletionParams(doc_id, Position(12, 14), missing), server, nothing)
            textDocument_hover_request(TextDocumentPositionParams(doc_id, Position(9, 13)), server, nothing)
            textDocument_definition_request(TextDocumentPositionParams(doc_id, Position(9, 23)), server, nothing)
            textDocument_documentSymbol_request(DocumentSymbolParams(doc_id, missing, missing), server, nothing)

            JuliaWorkspaces.get_diagnostics(server.workspace)
            JuliaWorkspaces.get_test_items(server.workspace)

            textDocument_didClose_notification(
                DidCloseTextDocumentParams(doc_id), server, nothing)
        end
    end
end
precompile(runserver, ())
