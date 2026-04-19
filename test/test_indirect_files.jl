@testitem "Indirect files: watcher registration via reconcile" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, get_indirect_files, is_indirect_file, has_file, TextFile, SourceText

    # In-process LS with dynamic-registration capabilities enabled so the
    # reconcile function actually emits register/unregister.
    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.runlinter = true
    server.jr_endpoint = nothing  # JSONRPC.send is stubbed to a no-op below
    @eval LanguageServer.JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

    # Fake clientCapabilities that pass the dynamic-registration gate.
    server.clientCapabilities = LanguageServer.ClientCapabilities(
        LanguageServer.WorkspaceClientCapabilities(
            true,
            LanguageServer.WorkspaceEditClientCapabilities(true, missing, missing),
            LanguageServer.DidChangeConfigurationClientCapabilities(false),
            LanguageServer.DidChangeWatchedFilesClientCapabilities(true, true),
            LanguageServer.WorkspaceSymbolClientCapabilities(true, missing),
            LanguageServer.ExecuteCommandClientCapabilities(true),
            missing,
            missing
        ),
        missing,
        missing,
        missing
    )

    mktempdir() do dir
        a_path = joinpath(dir, "A.jl")
        b_path = joinpath(dir, "B.jl")
        write(a_path, """include("B.jl")\nfoo() = 1\n""")
        write(b_path, "bar() = 2\n")

        a_uri = filepath2uri(a_path)
        b_uri = filepath2uri(b_path)

        # Add A.jl as a regular workspace file.
        a_text = TextFile(a_uri, SourceText(read(a_path, String), "julia"))
        JuliaWorkspaces.add_file!(server.workspace, a_text)

        # Trigger include traversal → JW lazily reads B.jl from disc and marks it indirect.
        JuliaWorkspaces.get_julia_files(server.workspace)
        @test is_indirect_file(server.workspace, b_uri)

        # Reconcile should register a watcher for B.jl.
        LanguageServer.reconcile_indirect_file_watchers(server)
        @test haskey(server._watched_indirect_files, b_uri)

        # Reconcile is idempotent: no second registration.
        original_id = server._watched_indirect_files[b_uri]
        LanguageServer.reconcile_indirect_file_watchers(server)
        @test server._watched_indirect_files[b_uri] === original_id
    end
end

@testitem "Indirect files: didChangeWatchedFiles routes to set_indirect_file_content!" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, is_indirect_file, has_file, TextFile, SourceText, get_julia_files

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    @eval LanguageServer.JSONRPC.send(::Nothing, ::Any, ::Any) = nothing
    server.clientCapabilities = LanguageServer.ClientCapabilities(
        LanguageServer.WorkspaceClientCapabilities(
            true,
            LanguageServer.WorkspaceEditClientCapabilities(true, missing, missing),
            LanguageServer.DidChangeConfigurationClientCapabilities(false),
            LanguageServer.DidChangeWatchedFilesClientCapabilities(true, true),
            LanguageServer.WorkspaceSymbolClientCapabilities(true, missing),
            LanguageServer.ExecuteCommandClientCapabilities(true),
            missing,
            missing
        ),
        missing, missing, missing
    )

    mktempdir() do dir
        a_path = joinpath(dir, "A.jl")
        b_path = joinpath(dir, "B.jl")
        write(a_path, """include("B.jl")\n""")
        write(b_path, "x = 1\n")

        a_uri = filepath2uri(a_path)
        b_uri = filepath2uri(b_path)

        JuliaWorkspaces.add_file!(server.workspace, TextFile(a_uri, SourceText(read(a_path, String), "julia")))
        JuliaWorkspaces.get_julia_files(server.workspace)
        LanguageServer.reconcile_indirect_file_watchers(server)
        @test haskey(server._watched_indirect_files, b_uri)

        # Simulate the client telling us B.jl changed on disc.
        write(b_path, "y = 42\n")
        change = LanguageServer.FileEvent(b_uri, LanguageServer.FileChangeTypes.Changed)
        params = LanguageServer.DidChangeWatchedFilesParams([change])
        LanguageServer.workspace_didChangeWatchedFiles_notification(params, server, nothing)

        @test is_indirect_file(server.workspace, b_uri)
        @test !has_file(server.workspace, b_uri)
        # Content was routed through set_indirect_file_content!.
        tf = JuliaWorkspaces.input_indirect_text_file(server.workspace.runtime, b_uri)
        @test tf !== nothing
        @test tf.content.content == "y = 42\n"

        # Simulate deletion.
        del = LanguageServer.FileEvent(b_uri, LanguageServer.FileChangeTypes.Deleted)
        LanguageServer.workspace_didChangeWatchedFiles_notification(LanguageServer.DidChangeWatchedFilesParams([del]), server, nothing)
        @test !(b_uri in get_julia_files(server.workspace))
    end
end

@testitem "Indirect files: didOpen promotes and reconcile unregisters" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, is_indirect_file, has_file, TextFile, SourceText

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    @eval LanguageServer.JSONRPC.send(::Nothing, ::Any, ::Any) = nothing
    server.clientCapabilities = LanguageServer.ClientCapabilities(
        LanguageServer.WorkspaceClientCapabilities(
            true,
            LanguageServer.WorkspaceEditClientCapabilities(true, missing, missing),
            LanguageServer.DidChangeConfigurationClientCapabilities(false),
            LanguageServer.DidChangeWatchedFilesClientCapabilities(true, true),
            LanguageServer.WorkspaceSymbolClientCapabilities(true, missing),
            LanguageServer.ExecuteCommandClientCapabilities(true),
            missing,
            missing
        ),
        missing, missing, missing
    )

    mktempdir() do dir
        a_path = joinpath(dir, "A.jl")
        b_path = joinpath(dir, "B.jl")
        write(a_path, """include("B.jl")\n""")
        write(b_path, "x = 1\n")

        a_uri = filepath2uri(a_path)
        b_uri = filepath2uri(b_path)

        JuliaWorkspaces.add_file!(server.workspace, TextFile(a_uri, SourceText(read(a_path, String), "julia")))
        JuliaWorkspaces.get_julia_files(server.workspace)
        LanguageServer.reconcile_indirect_file_watchers(server)
        @test haskey(server._watched_indirect_files, b_uri)
        @test is_indirect_file(server.workspace, b_uri)

        # User opens B.jl in the editor → didOpen → promotion via add_file!.
        params = LanguageServer.DidOpenTextDocumentParams(
            LanguageServer.TextDocumentItem(b_uri, "julia", 1, "x = 1\n")
        )
        LanguageServer.textDocument_didOpen_notification(params, server, nothing)

        @test has_file(server.workspace, b_uri)
        @test !is_indirect_file(server.workspace, b_uri)
        # Reconcile inside publish_diagnostics_testitems should have unregistered.
        @test !haskey(server._watched_indirect_files, b_uri)
    end
end

@testitem "Indirect files: no diagnostics published for indirect file" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, is_indirect_file, TextFile, SourceText, get_diagnostic

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    @eval LanguageServer.JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

    mktempdir() do dir
        a_path = joinpath(dir, "A.jl")
        b_path = joinpath(dir, "B.jl")
        write(a_path, """include("B.jl")\n""")
        write(b_path, "function foo() end begin")  # syntax error

        a_uri = filepath2uri(a_path)
        b_uri = filepath2uri(b_path)

        JuliaWorkspaces.add_file!(server.workspace, TextFile(a_uri, SourceText(read(a_path, String), "julia")))
        JuliaWorkspaces.get_julia_files(server.workspace)

        @test is_indirect_file(server.workspace, b_uri)
        @test isempty(get_diagnostic(server.workspace, b_uri))
    end
end
