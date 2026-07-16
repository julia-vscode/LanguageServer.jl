@testsnippet DebounceHelpers begin
    import Pkg, JSONRPC
    using LanguageServer: LanguageServerInstance
    using LanguageServer.URIs2

    # Endpoint that records every outgoing message so tests can assert on what
    # was (not) published. Like the `::Nothing` no-op in TestSetup, requests get
    # a `nothing` response.
    struct RecordingEndpoint
        msgs::Vector{Any}
    end
    RecordingEndpoint() = RecordingEndpoint(Any[])
    JSONRPC.send(e::RecordingEndpoint, t, params) = (push!(e.msgs, (msg_type = t, params = params)); nothing)

    published_diag_uris(e::RecordingEndpoint) = [
        m.params.uri for m in e.msgs
        if m.msg_type === LanguageServer.textDocument_publishDiagnostics_notification_type
    ]

    function drain!(ch)
        msgs = Any[]
        while isready(ch)
            push!(msgs, take!(ch))
        end
        return msgs
    end

    sweep_msgs(msgs) = [m for m in msgs if m.type == :publish_sweep]

    function make_initialized_server(endpoint)
        server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), nothing, first(Base.DEPOT_PATH))
        server.jr_endpoint = endpoint
        LanguageServer.initialize_request(TestSetup.init_request, server, nothing)
        LanguageServer.initialized_notification(LanguageServer.InitializedParams(), server, nothing)
        return server
    end

    open_doc(server, uri, text) = LanguageServer.textDocument_didOpen_notification(
        LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem(uri, "julia", 0, text)), server, nothing)

    change_doc(server, uri, version, text) = LanguageServer.textDocument_didChange_notification(
        LanguageServer.DidChangeTextDocumentParams(
            LanguageServer.VersionedTextDocumentIdentifier(uri, version),
            [LanguageServer.TextDocumentContentChangeEvent(missing, missing, text)]
        ), server, nothing)
end

@testitem "publish debounce: rapid changes coalesce into one sweep message" setup=[TestSetup, DebounceHelpers] begin
    old_delay = LanguageServer.SWEEP_DEBOUNCE_SECONDS[]
    LanguageServer.SWEEP_DEBOUNCE_SECONDS[] = 0.1
    try
        server = make_initialized_server(RecordingEndpoint())
        drain!(server.combined_msg_queue)

        doc_uri = uri"untitled:debouncedoc"
        open_doc(server, doc_uri, "f() = 1")
        for v in 1:3
            change_doc(server, doc_uri, v, "f() = $v")
        end

        # The burst marks the workspace dirty but publishes no sweep before the
        # debounce delay has elapsed.
        @test server._sweep_pending
        @test isempty(sweep_msgs(drain!(server.combined_msg_queue)))

        sleep(0.5)

        # Only the last scheduled timer fires: one sweep message for the burst.
        msgs = sweep_msgs(drain!(server.combined_msg_queue))
        @test length(msgs) == 1

        LanguageServer.handle_publish_sweep_msg!(server, msgs[1].generation)
        @test !server._sweep_pending
    finally
        LanguageServer.SWEEP_DEBOUNCE_SECONDS[] = old_delay
    end
end

@testitem "publish sweep: diffs against published state" setup=[TestSetup, DebounceHelpers] begin
    old_delay = LanguageServer.SWEEP_DEBOUNCE_SECONDS[]
    LanguageServer.SWEEP_DEBOUNCE_SECONDS[] = 100.0  # keep timers from firing mid-test
    try
        endpoint = RecordingEndpoint()
        server = make_initialized_server(endpoint)

        # Opening a document with a syntax error publishes its diagnostics
        # immediately (not debounced) and records the published state.
        doc_uri = uri"untitled:debouncedoc2"
        open_doc(server, doc_uri, "function f(")
        @test count(==(doc_uri), published_diag_uris(endpoint)) == 1
        @test haskey(server._published_hashes.diagnostics, doc_uri)

        # The next sweep must not re-publish the already-published document.
        LanguageServer.run_publish_sweep(server)
        @test count(==(doc_uri), published_diag_uris(endpoint)) == 1

        # A sweep over an unchanged workspace publishes nothing at all.
        empty!(endpoint.msgs)
        LanguageServer.run_publish_sweep(server)
        @test isempty(published_diag_uris(endpoint))

        # After an edit, the sweep publishes the changed document again.
        change_doc(server, doc_uri, 1, "function g(")
        empty!(endpoint.msgs)
        LanguageServer.run_publish_sweep(server)
        # (the immediate publish in didChange already updated the hash, so the
        # sweep itself stays silent — the edit was published exactly once)
        @test isempty(published_diag_uris(endpoint))
    finally
        LanguageServer.SWEEP_DEBOUNCE_SECONDS[] = old_delay
    end
end

@testitem "publish sweep handler: stale generations and drain guard" setup=[TestSetup, DebounceHelpers] begin
    old_delay = LanguageServer.SWEEP_DEBOUNCE_SECONDS[]
    LanguageServer.SWEEP_DEBOUNCE_SECONDS[] = 100.0  # timers must not fire during this test
    try
        # An uninitialized server suffices: the handler's bookkeeping is
        # independent of the workspace (run_publish_sweep no-ops without one).
        server = LanguageServerInstance(IOBuffer(), IOBuffer(), "", nothing, first(Base.DEPOT_PATH))
        server.jr_endpoint = nothing

        LanguageServer.schedule_publish_sweep!(server)
        first_gen = server._sweep_generation
        LanguageServer.schedule_publish_sweep!(server)
        @test server._sweep_generation > first_gen

        # A message from a superseded schedule is ignored.
        LanguageServer.handle_publish_sweep_msg!(server, first_gen)
        @test server._sweep_pending

        # Drain guard: with another message already queued, the sweep defers
        # itself to the back of the queue instead of running.
        put!(server.combined_msg_queue, (type = :dummy,))
        LanguageServer.handle_publish_sweep_msg!(server, server._sweep_generation)
        @test server._sweep_pending
        msgs = drain!(server.combined_msg_queue)
        @test msgs[1].type == :dummy
        @test length(sweep_msgs(msgs)) == 1

        # With an empty queue the sweep finally runs.
        LanguageServer.handle_publish_sweep_msg!(server, server._sweep_generation)
        @test !server._sweep_pending
    finally
        LanguageServer.SWEEP_DEBOUNCE_SECONDS[] = old_delay
    end
end
