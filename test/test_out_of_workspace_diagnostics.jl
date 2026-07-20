@testitem "Diagnostics: none emitted for files outside workspace folders" begin
    import Pkg
    import LanguageServer
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    import JuliaWorkspaces
    import JSONRPC, JSON

    # A real endpoint marked "running" but with no writer task: `send` just
    # enqueues serialized messages onto `out_msg_queue`, which we drain and
    # inspect to see what would have been published to the client.
    endpoint = JSONRPC.JSONRPCEndpoint(Base.BufferStream(), Base.BufferStream())
    endpoint.status = JSONRPC.status_running

    function drain_published(endpoint)
        published = Dict{String,Any}()
        while isready(endpoint.out_msg_queue)
            msg = JSON.parse(String(take!(endpoint.out_msg_queue)))
            if get(msg, "method", "") == "textDocument/publishDiagnostics"
                published[msg["params"]["uri"]] = msg["params"]["diagnostics"]
            end
        end
        return published
    end

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.workspace = JuliaWorkspaces.JuliaWorkspace()
    server.jr_endpoint = endpoint
    # Exercise the push path (publish_diagnostics) rather than the refresh request.
    server.clientcapability_workspace_diagnostic_refreshsupport = false

    mktempdir() do in_dir
        mktempdir() do out_dir
            in_path = joinpath(in_dir, "A.jl")
            out_path = joinpath(out_dir, "B.jl")
            src = "function foo() end begin"  # syntax error

            in_uri = filepath2uri(in_path)
            out_uri = filepath2uri(out_path)

            # `in_dir` is a workspace folder; `out_dir` is not.
            push!(server.workspaceFolders, in_dir)

            LanguageServer.textDocument_didOpen_notification(
                LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(in_uri, "julia", 0, src)),
                server, server.jr_endpoint)
            LanguageServer.textDocument_didOpen_notification(
                LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(out_uri, "julia", 0, src)),
                server, server.jr_endpoint)

            # Both files are tracked, but only the in-workspace one counts as a
            # workspace file.
            @test JuliaWorkspaces.has_file(server.workspace, in_uri)
            @test JuliaWorkspaces.has_file(server.workspace, out_uri)
            @test LanguageServer.is_workspace_file(server, in_uri)
            @test !LanguageServer.is_workspace_file(server, out_uri)

            # JuliaWorkspaces itself still computes the diagnostic for the outside
            # file (it stays generic); the LS is what refuses to emit it.
            @test !isempty(JuliaWorkspaces.get_diagnostic(server.workspace, out_uri))

            # Push path: published for the in-workspace file, never for the outside file.
            published = drain_published(endpoint)
            @test haskey(published, string(in_uri)) && !isempty(published[string(in_uri)])
            @test !haskey(published, string(out_uri))

            # Single-document pull returns an empty report for the outside file.
            in_pull = LanguageServer.textDocument_diagnostic_request(
                LanguageServer.DocumentDiagnosticParams(LanguageServer.TextDocumentIdentifier(in_uri), missing, missing),
                server, server.jr_endpoint)
            out_pull = LanguageServer.textDocument_diagnostic_request(
                LanguageServer.DocumentDiagnosticParams(LanguageServer.TextDocumentIdentifier(out_uri), missing, missing),
                server, server.jr_endpoint)
            @test !isempty(in_pull.items)
            @test isempty(out_pull.items)

            # Workspace-wide pull excludes the outside file.
            wpull = LanguageServer.workspace_diagnostic_request(
                LanguageServer.WorkspaceDiagnosticParams(missing, LanguageServer.PreviousResultId[]),
                server, server.jr_endpoint)
            reported = Set(string(i.uri) for i in wpull.items)
            @test string(in_uri) in reported
            @test !(string(out_uri) in reported)
        end
    end
end
