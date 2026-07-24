@testitem "Progress callback with workDoneProgress support" begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, create_progress_callback,
        WorkDoneProgressBegin, WorkDoneProgressReport, WorkDoneProgressEnd,
        WorkDoneProgressCreateParams, ProgressParams,
        window_workDoneProgress_create_request_type, progress_notification_type

    # Capture JSONRPC.send calls on Nothing endpoint (same pattern as test_shared_server.jl)
    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.clientcapability_window_workdoneprogress = true

    cb = create_progress_callback(server)

    # Reports are delivered asynchronously by the worker task that owns the
    # progress tokens, so wait for the expected number of sends.
    wait_for_sends(n) = timedwait(() -> length(sent) >= n, 5.0) === :ok

    # First report for a phase → create + Begin
    cb("download:/p", "Downloading caches...", 10)
    @test wait_for_sends(2)
    @test sent[1][1] === window_workDoneProgress_create_request_type
    @test sent[1][2] isa WorkDoneProgressCreateParams
    dl_token = sent[1][2].token
    @test startswith(dl_token, "jw-")

    @test sent[2][1] === progress_notification_type
    @test sent[2][2] isa ProgressParams{WorkDoneProgressBegin}
    @test sent[2][2].token == dl_token
    @test sent[2][2].value.title == "Julia"
    @test sent[2][2].value.message == "Downloading package caches (0/1)..."
    @test sent[2][2].value.percentage == 10  # download keeps its real fraction (mean)

    # A different phase gets its own token — bars run concurrently.
    cb("index:/p", "Indexing project...", 5)
    @test wait_for_sends(4)
    @test sent[3][2] isa WorkDoneProgressCreateParams
    idx_token = sent[3][2].token
    @test idx_token != dl_token
    @test sent[4][2] isa ProgressParams{WorkDoneProgressBegin}
    @test sent[4][2].token == idx_token

    # Subsequent reports go to their phase's bar.
    cb("download:/p", "Downloading caches (50/100)...", 50)
    @test wait_for_sends(5)
    @test sent[5][2] isa ProgressParams{WorkDoneProgressReport}
    @test sent[5][2].token == dl_token
    @test sent[5][2].value.percentage == 50  # download keeps its real fraction (mean)

    # The phase's last key reaching 100 ends its bar.
    cb("download:/p", "Downloads done", 100)
    @test wait_for_sends(6)
    @test sent[6][2] isa ProgressParams{WorkDoneProgressEnd}
    @test sent[6][2].token == dl_token

    cb("index:/p", "Indexing Foo...", 40)
    @test wait_for_sends(7)
    @test sent[7][2] isa ProgressParams{WorkDoneProgressReport}
    @test sent[7][2].token == idx_token

    # A phase with no open bar is a no-op; ending the index bar works.
    cb("unknown-op", "Done", 100)
    cb("index:/p", "Done", 100)
    @test wait_for_sends(8)
    @test sent[8][2] isa ProgressParams{WorkDoneProgressEnd}
    @test sent[8][2].token == idx_token

    # After End, a new report for the same phase starts a fresh bar.
    empty!(sent)
    cb("index:/p", "Re-indexing...", 5)
    @test wait_for_sends(2)  # new create + begin
    @test sent[1][2].token != idx_token

    # The callback itself must never block: enqueueing a burst returns
    # immediately and every report is delivered to the open bar. With one
    # in-progress key the count-based percentage stays 0 until it completes,
    # so delivery is verified by the send count and shared token.
    empty!(sent)
    for i in 1:10
        cb("index:/p", "Report $i", 10 + i)
    end
    @test wait_for_sends(10)
    @test all(p.token == sent[1][2].token for (_, p) in sent)
    @test all(p.value.percentage == 0 for (_, p) in sent)
end

@testitem "Progress bars aggregate by phase" begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, create_progress_callback,
        WorkDoneProgressBegin, WorkDoneProgressReport, WorkDoneProgressEnd,
        ProgressParams

    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.clientcapability_window_workdoneprogress = true

    cb = create_progress_callback(server)
    wait_for_sends(n) = timedwait(() -> length(sent) >= n, 5.0) === :ok

    # Three environments preparing to index share ONE bar, not three.
    cb("index:/a", "Preparing to index...", 0)
    @test wait_for_sends(2)  # create + begin
    token = sent[2][2].token
    @test sent[2][2].value.message == "Indexing environments (0/1)..."

    cb("index:/b", "Preparing to index...", 0)
    cb("index:/c", "Preparing to index...", 0)
    @test wait_for_sends(4)
    @test all(p.token == token for (_, p) in sent[3:4])  # no new tokens created
    @test sent[4][2].value.message == "Indexing environments (0/3)..."

    # Only completed envs advance the bar; an in-progress env (a at 50%) does not.
    cb("index:/a", "Indexing Foo...", 50)
    cb("index:/b", "Indexing Bar...", 100)
    @test wait_for_sends(6)
    @test sent[6][2] isa ProgressParams{WorkDoneProgressReport}
    @test sent[6][2].value.message == "Indexing environments (1/3)..."
    @test sent[6][2].value.percentage == 33  # 1 of 3 completed; a's in-progress 50% is ignored

    # The bar ends only once every key has completed.
    cb("index:/a", "Done", 100)
    @test wait_for_sends(7)
    @test sent[7][2] isa ProgressParams{WorkDoneProgressReport}
    cb("index:/c", "Done", 100)
    @test wait_for_sends(8)
    @test sent[8][2] isa ProgressParams{WorkDoneProgressEnd}
    @test sent[8][2].token == token
end

@testitem "Progress callback without workDoneProgress support" begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, create_progress_callback

    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.clientcapability_window_workdoneprogress = false

    cb = create_progress_callback(server)

    # Should be a no-op — no sends at all
    cb("op", "Downloading...", 10)
    cb("op", "Indexing...", 50)
    cb("op", "Done", 100)
    sleep(0.5)
    @test isempty(sent)
end

@testitem "Progress callback with nil endpoint" begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, create_progress_callback

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.clientcapability_window_workdoneprogress = true

    # With JSONRPC.send(::Nothing,...) defined, callback should work without error
    JSONRPC.send(::Nothing, typ, params) = nothing

    cb = create_progress_callback(server)

    cb("op", "test", 10)
    sleep(0.5)
    @test true  # if we got here without error, the test passes
end
