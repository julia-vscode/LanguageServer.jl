@testitem "Server status: snapshots are forwarded as julia/publishServerStatus" begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, create_status_callback, server_status_enabled,
        julia_publishServerStatus_notification_type, PublishServerStatusParams, ServerStatusDJPDetail

    # Capture JSONRPC.send calls on Nothing endpoint (same pattern as test_progress.jl)
    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.initialization_options = Dict("julialangServerStatus" => true)
    @test server_status_enabled(server)

    cb = create_status_callback(server)
    wait_for_sends(n) = timedwait(() -> length(sent) >= n, 5.0) === :ok

    # Duck-typed stand-in for JuliaWorkspaces.DynamicStatusSnapshot (same
    # fields), so this test also runs against a JuliaWorkspaces version that
    # predates the type; see the guard notes in serverstatus.jl.
    item(; kind, path, package=nothing, status, progress=nothing, failure_message=nothing, alive=false) =
        (; kind, path, package, status, progress, failure_message, alive)
    snapshot = (indexing_done=false, pending_count=2, max_concurrent_djps=4, items=[
        item(kind=:watch_environment, path="/ws/A", status=:running, progress=40, alive=true),
        item(kind=:watch_test_environment, path="/ws/B", package="B", status=:queued),
        item(kind=:watch_environment, path="/ws/C", status=:failed, failure_message="Failed to resolve the environment at /ws/C."),
    ])
    cb(snapshot)
    @test wait_for_sends(1)

    typ, params = sent[1]
    @test typ === julia_publishServerStatus_notification_type
    @test params isa PublishServerStatusParams
    @test !params.indexingDone
    @test params.pendingCount == 2
    @test params.maxConcurrentDjps == 4
    @test length(params.djps) == 3

    a, b, c = params.djps
    @test a.kind == "watch_environment"
    @test a.path == "/ws/A"
    @test a.package === missing
    @test a.status == "running"
    @test a.progress == 40
    @test a.failureMessage === missing
    @test a.alive

    @test b.kind == "watch_test_environment"
    @test b.package == "B"
    @test b.status == "queued"
    @test b.progress === missing
    @test !b.alive

    @test c.status == "failed"
    @test c.failureMessage == "Failed to resolve the environment at /ws/C."
end

@testitem "Server status: a burst of snapshots coalesces to the newest" begin
    import Pkg, JSONRPC
    using LanguageServer
    using LanguageServer: LanguageServerInstance, create_status_callback, PublishServerStatusParams

    sent = []
    JSONRPC.send(::Nothing, typ, params) = push!(sent, (typ, params))

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))
    server.jr_endpoint = nothing
    server.initialization_options = Dict("julialangServerStatus" => true)

    cb = create_status_callback(server)

    # The callback never blocks; the worker rate-limits and keeps only the
    # newest queued snapshot, so the final state always arrives but the burst
    # must not turn into one notification per snapshot.
    n = 50
    for i in 1:n
        cb((indexing_done=(i == n), pending_count=n - i, max_concurrent_djps=4, items=[]))
    end

    @test timedwait(() -> !isempty(sent) && last(sent)[2].indexingDone, 10.0) === :ok
    @test last(sent)[2].pendingCount == 0
    @test length(sent) < n
end

@testitem "Server status: disabled without the julialangServerStatus init option" begin
    import Pkg
    using LanguageServer
    using LanguageServer: LanguageServerInstance, server_status_enabled

    server = LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file))

    # Never initialized: missing options.
    @test !server_status_enabled(server)

    # Initialized without the option.
    server.initialization_options = Dict{String,Any}()
    @test !server_status_enabled(server)

    # Explicitly disabled.
    server.initialization_options = Dict("julialangServerStatus" => false)
    @test !server_status_enabled(server)

    server.initialization_options = Dict("julialangServerStatus" => true)
    @test server_status_enabled(server)
end
