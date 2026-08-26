# An atomic folder rename or delete reaches the server as a single
# didChangeWatchedFiles event for the folder path, with no events for the files
# inside. These tests cover the folder handling in
# workspace_didChangeWatchedFiles_notification.

@testitem "Watched folders: folder delete sweeps children but not siblings" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, has_file
    import JSONRPC
    JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.workspace = JuliaWorkspaces.JuliaWorkspace()

    mktempdir() do dir
        test_dir = joinpath(dir, "test")
        sibling_dir = joinpath(dir, "test2")
        mkpath(joinpath(test_dir, "sub"))
        mkpath(sibling_dir)
        a_path = joinpath(test_dir, "a.jl")
        b_path = joinpath(test_dir, "sub", "b.jl")
        c_path = joinpath(sibling_dir, "c.jl")
        for p in (a_path, b_path, c_path)
            write(p, "f() = 1\n")
        end

        changed = LanguageServer.add_folder_children!(server, dir)
        a_uri, b_uri, c_uri = filepath2uri.((a_path, b_path, c_path))
        @test Set(changed) == Set([a_uri, b_uri, c_uri])
        @test has_file(server.workspace, a_uri)
        @test has_file(server.workspace, b_uri)

        # Delete the folder on disc and report only the folder-level event, the
        # way an atomic rename/delete arrives.
        test_dir_uri = filepath2uri(test_dir)
        rm(test_dir, recursive=true)
        params = LanguageServer.DidChangeWatchedFilesParams([
            LanguageServer.FileEvent(test_dir_uri, LanguageServer.FileChangeTypes.Deleted),
        ])
        LanguageServer.workspace_didChangeWatchedFiles_notification(params, server, nothing)

        @test !has_file(server.workspace, a_uri)
        @test !has_file(server.workspace, b_uri)
        @test !haskey(server._files_from_disc, a_uri)
        @test !haskey(server._files_from_disc, b_uri)
        @test !(a_uri in server._workspace_files)
        @test !(b_uri in server._workspace_files)

        # `test2` is a sibling whose path shares the `test` prefix; it must
        # survive the sweep.
        @test has_file(server.workspace, c_uri)
        @test haskey(server._files_from_disc, c_uri)
        @test c_uri in server._workspace_files
    end
end

@testitem "Watched folders: folder create scans children" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, has_file
    import JSONRPC
    JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.workspace = JuliaWorkspaces.JuliaWorkspace()

    mktempdir() do dir
        new_dir = joinpath(dir, "test2")
        mkpath(joinpath(new_dir, "sub"))
        a_path = joinpath(new_dir, "a.jl")
        b_path = joinpath(new_dir, "sub", "b.jl")
        other_path = joinpath(new_dir, "data.bin")
        write(a_path, "f() = 1\n")
        write(b_path, "g() = 2\n")
        write(other_path, "not julia")

        # Report only the folder-level create, the way an atomic rename arrives.
        params = LanguageServer.DidChangeWatchedFilesParams([
            LanguageServer.FileEvent(filepath2uri(new_dir), LanguageServer.FileChangeTypes.Created),
        ])
        LanguageServer.workspace_didChangeWatchedFiles_notification(params, server, nothing)

        a_uri, b_uri, other_uri = filepath2uri.((a_path, b_path, other_path))
        @test has_file(server.workspace, a_uri)
        @test has_file(server.workspace, b_uri)
        @test a_uri in server._workspace_files
        @test b_uri in server._workspace_files
        @test !has_file(server.workspace, other_uri)
    end
end

@testitem "Watched folders: rename reported as delete + create" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, has_file
    import JSONRPC
    JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.workspace = JuliaWorkspaces.JuliaWorkspace()

    mktempdir() do dir
        old_dir = joinpath(dir, "test")
        mkpath(old_dir)
        write(joinpath(old_dir, "a.jl"), "f() = 1\n")
        LanguageServer.add_folder_children!(server, dir)

        old_uri = filepath2uri(joinpath(old_dir, "a.jl"))
        @test has_file(server.workspace, old_uri)

        new_dir = joinpath(dir, "test2")
        mv(old_dir, new_dir)
        params = LanguageServer.DidChangeWatchedFilesParams([
            LanguageServer.FileEvent(filepath2uri(old_dir), LanguageServer.FileChangeTypes.Deleted),
            LanguageServer.FileEvent(filepath2uri(new_dir), LanguageServer.FileChangeTypes.Created),
        ])
        LanguageServer.workspace_didChangeWatchedFiles_notification(params, server, nothing)

        new_uri = filepath2uri(joinpath(new_dir, "a.jl"))
        @test !has_file(server.workspace, old_uri)
        @test has_file(server.workspace, new_uri)
        @test new_uri in server._workspace_files
        @test !(old_uri in server._workspace_files)
    end
end

@testitem "Watched folders: open files under a deleted folder stay in the workspace" begin
    import Pkg
    using LanguageServer.URIs2
    using LanguageServer: LanguageServerInstance
    using JuliaWorkspaces: JuliaWorkspaces, has_file
    import JSONRPC
    JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.workspace = JuliaWorkspaces.JuliaWorkspace()

    mktempdir() do dir
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)
        open_path = joinpath(test_dir, "open.jl")
        closed_path = joinpath(test_dir, "closed.jl")
        write(open_path, "f() = 1\n")
        write(closed_path, "g() = 2\n")
        LanguageServer.add_folder_children!(server, dir)

        open_uri = filepath2uri(open_path)
        closed_uri = filepath2uri(closed_path)
        # Pretend the editor has open.jl open.
        server._open_file_versions[open_uri] = 1

        rm(test_dir, recursive=true)
        params = LanguageServer.DidChangeWatchedFilesParams([
            LanguageServer.FileEvent(filepath2uri(test_dir), LanguageServer.FileChangeTypes.Deleted),
        ])
        LanguageServer.workspace_didChangeWatchedFiles_notification(params, server, nothing)

        # The open file keeps its in-memory content until the editor closes it;
        # only its from-disc record is dropped.
        @test has_file(server.workspace, open_uri)
        @test !haskey(server._files_from_disc, open_uri)
        @test !has_file(server.workspace, closed_uri)
    end
end
