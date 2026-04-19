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

    # First call → Begin
    cb("Downloading caches...", 10)
    @test length(sent) == 2  # create + begin
    @test sent[1][1] === window_workDoneProgress_create_request_type
    @test sent[1][2] isa WorkDoneProgressCreateParams
    token = sent[1][2].token
    @test startswith(token, "jw-indexing-")

    @test sent[2][1] === progress_notification_type
    @test sent[2][2] isa ProgressParams{WorkDoneProgressBegin}
    @test sent[2][2].token == token
    @test sent[2][2].value.title == "Julia"
    @test sent[2][2].value.message == "Downloading caches..."
    @test sent[2][2].value.percentage == 10

    # Subsequent call → Report
    cb("Indexing project...", 50)
    @test length(sent) == 3
    @test sent[3][1] === progress_notification_type
    @test sent[3][2] isa ProgressParams{WorkDoneProgressReport}
    @test sent[3][2].value.message == "Indexing project..."
    @test sent[3][2].value.percentage == 50

    # Final call → End
    cb("Indexing complete", 100)
    @test length(sent) == 4
    @test sent[4][1] === progress_notification_type
    @test sent[4][2] isa ProgressParams{WorkDoneProgressEnd}
    @test sent[4][2].value.message == "Indexing complete"

    # After End, a new call starts a fresh session
    empty!(sent)
    cb("Re-indexing...", 5)
    @test length(sent) == 2  # new create + begin
    new_token = sent[1][2].token
    @test new_token != token  # different token
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
    cb("Downloading...", 10)
    cb("Indexing...", 50)
    cb("Done", 100)
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

    cb("test", 10)
    @test true  # if we got here without error, the test passes
end
