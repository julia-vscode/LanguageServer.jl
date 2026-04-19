"""
    create_progress_callback(server::LanguageServerInstance) -> Function

Return a closure `(message::String, percentage::Int) -> Nothing` that translates
JuliaWorkspaces progress updates into LSP `\$/progress` notifications.

The closure manages a single progress token lifecycle:
- On the first call it creates a token via `window/workDoneProgress/create` and
  sends `WorkDoneProgressBegin`.
- Subsequent calls send `WorkDoneProgressReport` with message and percentage.
- When percentage reaches 100 it sends `WorkDoneProgressEnd` and resets, ready
  for a new round (e.g. after a manifest change triggers re-indexing).
"""
function create_progress_callback(server::LanguageServerInstance)
    # Mutable state captured by the closure.
    active = Ref(false)
    token = Ref("")

    return function (message::String, percentage::Int)
        # Guard: do nothing when the client doesn't support work-done progress
        # or the endpoint isn't ready yet.
        server.clientcapability_window_workdoneprogress || return
        ep = server.jr_endpoint

        if !active[]
            # Start a new progress session
            token[] = "jw-indexing-$(UUIDs.uuid4())"
            try
                JSONRPC.send(ep, window_workDoneProgress_create_request_type, WorkDoneProgressCreateParams(token[]))
            catch err
                @warn "Failed to create progress token" exception=(err, catch_backtrace())
                return
            end
            JSONRPC.send(ep, progress_notification_type, ProgressParams(token[], WorkDoneProgressBegin("Julia", false, message, percentage)))
            active[] = true
        elseif percentage >= 100
            JSONRPC.send(ep, progress_notification_type, ProgressParams(token[], WorkDoneProgressEnd(message)))
            active[] = false
        else
            JSONRPC.send(ep, progress_notification_type, ProgressParams(token[], WorkDoneProgressReport(false, message, percentage)))
        end
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

    return function (message::String, percentage::Int)
        isassigned(server_ref) || return
        if inner_cb[] === nothing
            inner_cb[] = create_progress_callback(server_ref[])
        end
        inner_cb[](message, percentage)
        return
    end
end
