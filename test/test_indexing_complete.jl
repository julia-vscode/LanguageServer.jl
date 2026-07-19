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

@testitem "indexing-complete: second refresh with unchanged state publishes nothing" setup=[TestSetup] begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, handle_indexing_complete!
    using LanguageServer.URIs2

    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.enable_dynamic_indexing = false
    LanguageServer.initialize_request(TestSetup.init_request, server, nothing)
    LanguageServer.initialized_notification(LanguageServer.InitializedParams(), server, nothing)

    LanguageServer.textDocument_didOpen_notification(
        LanguageServer.DidOpenTextDocumentParams(
            LanguageServer.TextDocumentItem(uri"untitled:testdoc", "julia", 0, "f(x) = x\n")),
        server, nothing)

    # First refresh: no baseline yet, publishes the full state.
    empty!(sent)
    handle_indexing_complete!(server)
    @test length(sent) >= 1
    @test server._indexing_publish_marks !== nothing

    # Nothing changed since: a second refresh publishes nothing.
    empty!(sent)
    handle_indexing_complete!(server)
    @test isempty(sent)
end
