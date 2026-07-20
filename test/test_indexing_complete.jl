@testitem "indexing-complete: repeated requests coalesce to one queued message" begin
    import Pkg
    using LanguageServer: LanguageServerInstance, request_indexing_refresh

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))

    request_indexing_refresh(server)
    request_indexing_refresh(server)
    request_indexing_refresh(server)

    msgs = []
    while isready(server.combined_msg_queue)
        push!(msgs, take!(server.combined_msg_queue))
    end
    @test length(msgs) == 1

    # Once handled (flag reset), a new request queues again.
    server._indexing_complete_queued[] = false
    request_indexing_refresh(server)
    @test isready(server.combined_msg_queue)
end

@testitem "indexing-complete: refresh with unchanged state publishes nothing" setup=[TestSetup] begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, handle_indexing_complete!
    using LanguageServer.URIs2

    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    dir = mktempdir()
    write(joinpath(dir, "src.jl"), "f(x) = x\n")

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.enable_dynamic_indexing = false
    push!(server.workspaceFolders, dir)
    LanguageServer.initialize_request(TestSetup.init_request, server, nothing)
    LanguageServer.initialized_notification(LanguageServer.InitializedParams(), server, nothing)

    # The initial sweep during `initialized` publishes the workspace state and
    # records the baseline hashes.
    @test !isempty(sent)
    @test !isempty(server._published_hashes.diagnostics)

    # Nothing has changed since: an indexing-complete refresh diffs against the
    # recorded baseline and publishes nothing.
    empty!(sent)
    handle_indexing_complete!(server)
    @test isempty(sent)
end
