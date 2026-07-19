@testitem "initialized: initial sweep publishes from a worker task" setup=[TestSetup] begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance
    using LanguageServer.URIs2
    import JuliaWorkspaces

    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    dir = mktempdir()
    file = joinpath(dir, "src.jl")
    write(file, "function f(x)\n    return x\nend\n")
    file_uri = filepath2uri(file)

    published_file_diags() = any(sent) do (typ, params)
        params isa LanguageServer.PublishDiagnosticsParams && params.uri == file_uri
    end

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.enable_dynamic_indexing = false
    push!(server.workspaceFolders, dir)
    LanguageServer.initialize_request(TestSetup.init_request, server, nothing)
    LanguageServer.initialized_notification(LanguageServer.InitializedParams(), server, nothing)

    # The notification returns before the sweep ran: no diagnostics have been
    # published yet (nothing has yielded to the worker task).
    @test !published_file_diags()
    @test JuliaWorkspaces.has_file(server.workspace, file_uri)

    # Once the worker gets scheduled, the file's diagnostics arrive on the
    # wire and the publish baseline for indexing-complete refreshes is set.
    @test timedwait(published_file_diags, 120.0) === :ok
    @test timedwait(() -> server._indexing_publish_marks !== nothing, 120.0) === :ok
end

@testitem "initialized: one walk feeds workspace files, disc cache, and JW" setup=[TestSetup] begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance
    using LanguageServer.URIs2
    import JuliaWorkspaces

    JSONRPC.send(::Nothing, typ, params) = nothing

    dir = mktempdir()
    file = joinpath(dir, "code.jl")
    write(file, "g() = 1\n")
    write(joinpath(dir, "notes.md"), "# notes\n")

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.enable_dynamic_indexing = false
    push!(server.workspaceFolders, dir)
    LanguageServer.initialize_request(TestSetup.init_request, server, nothing)
    LanguageServer.initialized_notification(LanguageServer.InitializedParams(), server, nothing)

    file_uri = filepath2uri(file)
    md_uri = filepath2uri(joinpath(dir, "notes.md"))

    # julia files land in the workspace-file set; everything read lands in
    # the disc cache and the JW workspace.
    @test file_uri in server._workspace_files
    @test !(md_uri in server._workspace_files)
    @test haskey(server._files_from_disc, file_uri)
    @test haskey(server._files_from_disc, md_uri)
    @test JuliaWorkspaces.has_file(server.workspace, file_uri)

    # The former guard helpers are gone: one walk serves all consumers.
    @test !isdefined(LanguageServer, :has_too_many_files)
    @test !isdefined(LanguageServer, :load_folder)
end
