"""
    create_progress_callback(server::LanguageServerInstance) -> Function

Return a closure `(key::String, message::String, percentage::Int) -> Nothing`
that translates JuliaWorkspaces progress updates into LSP `\$/progress`
notifications.

Each distinct `key` is its own work-done-progress token (its own progress bar
on the client) with the full 0–100 percentage range, so concurrently running
operations — downloading caches, indexing different projects, loading caches —
are presented independently instead of being squeezed into slices of one bar.

The closure only enqueues the report and never blocks: a worker task owns the
token lifecycles and performs the client round-trips. This matters because the
callback is invoked from the dynamic-feature reactor, which must not stall on
`window/workDoneProgress/create` (a blocking client request) — reports arriving
while a token is being created queue up and are delivered in order.

Per-key lifecycle managed by the worker:
- The first report for a key creates a token via `window/workDoneProgress/create`
  and sends `WorkDoneProgressBegin`.
- Subsequent reports are sent as `WorkDoneProgressReport`.
- A report with `percentage >= 100` sends `WorkDoneProgressEnd`, retires the
  key (a later report for it starts a fresh bar), and requests a diagnostics
  refresh (coalesced: at most one `:jw_indexing_complete` is queued at a
  time). Ending a key that has no open bar is a no-op.
"""
function create_progress_callback(server::LanguageServerInstance)
    reports = Channel{Tuple{String,String,Int}}(Inf)

    @async try
        tokens = Dict{String,String}()

        for (key, message, percentage) in reports
            # Guard: do nothing when the client doesn't support work-done progress
            # or the endpoint isn't ready yet.
            server.clientcapability_window_workdoneprogress || continue
            ep = server.jr_endpoint

            token = get(tokens, key, nothing)
            if token === nothing
                # Ending an operation that never opened a bar is a no-op.
                percentage >= 100 && continue

                # Start a new progress bar for this operation
                token = "jw-$(UUIDs.uuid4())"
                try
                    JSONRPC.send(ep, window_workDoneProgress_create_request_type, WorkDoneProgressCreateParams(token))
                catch err
                    @warn "Failed to create progress token" exception=(err, catch_backtrace())
                    continue
                end
                JSONRPC.send(ep, progress_notification_type, ProgressParams(token, WorkDoneProgressBegin("Julia", false, message, percentage)))
                tokens[key] = token
            elseif percentage >= 100
                JSONRPC.send(ep, progress_notification_type, ProgressParams(token, WorkDoneProgressEnd(message)))
                delete!(tokens, key)
                request_indexing_refresh(server)
            else
                JSONRPC.send(ep, progress_notification_type, ProgressParams(token, WorkDoneProgressReport(false, message, percentage)))
            end
        end
    catch err
        @error "Progress reporting task failed" exception=(err, catch_backtrace())
    end

    return function (key::String, message::String, percentage::Int)
        put!(reports, (key, message, percentage))
        return
    end
end

"""
    _create_deferred_progress_callback(server_ref::Ref{LanguageServerInstance}) -> Function

Return a progress callback that defers to `create_progress_callback` once
`server_ref` has been assigned (after the inner constructor completes).
This allows the callback to be passed to JuliaWorkspace during construction
while the LanguageServerInstance is still being built.
"""
function _create_deferred_progress_callback(server_ref::Ref)
    inner_cb = Ref{Union{Nothing,Function}}(nothing)

    return function (key::String, message::String, percentage::Int)
        isassigned(server_ref) || return
        if inner_cb[] === nothing
            inner_cb[] = create_progress_callback(server_ref[])
        end
        inner_cb[](key, message, percentage)
        return
    end
end
