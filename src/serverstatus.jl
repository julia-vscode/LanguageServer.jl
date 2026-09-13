"""
    server_status_enabled(server)

Whether the client asked for `julia/publishServerStatus` notifications at
initialization. This is the single gate for all server-status work: when it is
off, no status callback is handed to JuliaWorkspaces, so the reactor never even
builds snapshots.
"""
function server_status_enabled(server)
    return !ismissing(server.initialization_options) &&
        get(server.initialization_options, "julialangServerStatus", false) == true
end

_status_missing(x) = x === nothing ? missing : x

# Duck-typed on purpose: `JuliaWorkspaces.DynamicStatusSnapshot` only exists
# from the version introduced in julia-vscode/JuliaWorkspaces.jl#316 on (after
# 13.4.0), and a type annotation here would be evaluated at package load time.
# Annotate once the compat lower bound requires a version that has the type.
function _server_status_params(snapshot)
    djps = [ServerStatusDJPDetail(
        string(item.kind),
        item.path,
        _status_missing(item.package),
        string(item.status),
        _status_missing(item.progress),
        _status_missing(item.failure_message),
        item.alive,
    ) for item in snapshot.items]
    return PublishServerStatusParams(snapshot.indexing_done, snapshot.pending_count, snapshot.max_concurrent_djps, djps)
end

# Floor between two notifications, so a burst of reactor activity (dozens of
# work items completing) costs the client a handful of updates, not hundreds.
const SERVER_STATUS_MIN_INTERVAL_SECONDS = 0.25

"""
    create_status_callback(server::LanguageServerInstance) -> Function

Return a closure `(snapshot) -> Nothing` taking a
`JuliaWorkspaces.DynamicStatusSnapshot`,
suitable as the `status_callback` of a `JuliaWorkspace`, forwarding snapshots
to the client as `julia/publishServerStatus` notifications.

The closure only enqueues the snapshot and never blocks (it is invoked on the
dynamic feature's reactor). A worker task drains the queue, keeping only the
newest snapshot when several queued up, and rate-limits sends to one per
$(SERVER_STATUS_MIN_INTERVAL_SECONDS)s.
"""
function create_status_callback(server::LanguageServerInstance)
    snapshots = Channel{Any}(Inf)

    @async try
        while true
            snapshot = take!(snapshots)
            # Coalesce: only the newest queued snapshot matters.
            while isready(snapshots)
                snapshot = take!(snapshots)
            end
            try
                JSONRPC.send(server.jr_endpoint, julia_publishServerStatus_notification_type, _server_status_params(snapshot))
            catch err
                @warn "Failed to publish server status" exception=(err, catch_backtrace())
            end
            sleep(SERVER_STATUS_MIN_INTERVAL_SECONDS)
        end
    catch err
        @error "Server status reporting task failed" exception=(err, catch_backtrace())
    end

    return function (snapshot)
        put!(snapshots, snapshot)
        return
    end
end
