"""
    create_progress_callback(server::LanguageServerInstance) -> Function

Return a closure `(key::String, message::String, percentage::Int) -> Nothing`
that translates JuliaWorkspaces progress updates into LSP `\$/progress`
notifications.

Reports are aggregated by *phase* — the part of `key` before `:` (`index`,
`download`, `refresh`), or the whole key for single-operation phases
(`package-caches`, `bootstrap`). Each phase is one bar, so a workspace with
dozens of environments shows a single "Indexing environments (k/N)..." bar
instead of dozens. For index/refresh the percentage tracks the count of
completed keys (`k/N`), so an in-progress environment never advances the bar
past that count; the download bar keeps the mean, since a download key carries
a real fraction. The bar ends once every key has reported `>= 100`.

The closure only enqueues the report and never blocks: a worker task owns the
token lifecycles and does the client round-trips, so a report arriving while a
token is being created queues up and is delivered in order.
"""
mutable struct PhaseBar
    token::String
    pct::Dict{String,Int}   # active key -> latest percentage
    seen::Set{String}       # every key that went active this cycle
    completed::Int
end

# Phase = key prefix before ':' (index/download/refresh), else the whole key.
function _progress_phase(key::String)
    i = findfirst(==(':'), key)
    return i === nothing ? key : key[1:prevind(key, i)]
end

# Record a report; :completed when it finished an active key, :noop when it
# ended a key that was never active (nothing to do), :updated otherwise.
function _update_phase!(bar::PhaseBar, key::String, percentage::Int)
    if percentage >= 100
        haskey(bar.pct, key) || return :noop
        delete!(bar.pct, key)
        bar.completed += 1
        return :completed
    end
    push!(bar.seen, key)
    bar.pct[key] = percentage
    return :updated
end

_phase_label(phase, completed, total, message) =
    phase == "index"    ? "Indexing environments ($completed/$total)..." :
    phase == "download" ? "Downloading package caches ($completed/$total)..." :
    phase == "refresh"  ? "Refreshing environments ($completed/$total)..." :
    message  # single-operation phases pass their message through

# Aggregate percentage + label for the phase's current state.
function _phase_report(phase::String, bar::PhaseBar, message::String)
    total = length(bar.seen)
    total == 0 && return (0, message)
    # Index/refresh keys are whole environments: only completed ones advance the
    # bar, so the fill never runs past the "(k/total)" count shown beside it. A
    # download key instead carries a real fraction, so its bar keeps the mean.
    pct = phase == "download" ?
        clamp(round(Int, (sum(values(bar.pct); init=0) + 100 * bar.completed) / total), 0, 100) :
        clamp(round(Int, 100 * bar.completed / total), 0, 100)
    return (pct, _phase_label(phase, bar.completed, total, message))
end

function create_progress_callback(server::LanguageServerInstance)
    reports = Channel{Tuple{String,String,Int}}(Inf)

    @async try
        bars = Dict{String,PhaseBar}()

        for (key, message, percentage) in reports
            # Do nothing when the client doesn't support work-done progress or
            # the endpoint isn't ready yet.
            server.clientcapability_window_workdoneprogress || continue
            ep = server.jr_endpoint

            phase = _progress_phase(key)
            bar = get(bars, phase, nothing)

            if bar === nothing
                # A terminal report has no bar to end.
                percentage >= 100 && continue
                token = "jw-$(UUIDs.uuid4())"
                try
                    JSONRPC.send(ep, window_workDoneProgress_create_request_type, WorkDoneProgressCreateParams(token))
                catch err
                    @warn "Failed to create progress token" exception=(err, catch_backtrace())
                    continue
                end
                bar = PhaseBar(token, Dict{String,Int}(), Set{String}(), 0)
                bars[phase] = bar
                _update_phase!(bar, key, percentage)
                pct, msg = _phase_report(phase, bar, message)
                JSONRPC.send(ep, progress_notification_type, ProgressParams(token, WorkDoneProgressBegin("Julia", false, msg, pct)))
            else
                status = _update_phase!(bar, key, percentage)
                status === :noop && continue
                status === :completed && request_indexing_refresh(server)

                if bar.completed >= length(bar.seen)
                    _, msg = _phase_report(phase, bar, message)
                    JSONRPC.send(ep, progress_notification_type, ProgressParams(bar.token, WorkDoneProgressEnd(msg)))
                    delete!(bars, phase)
                else
                    pct, msg = _phase_report(phase, bar, message)
                    JSONRPC.send(ep, progress_notification_type, ProgressParams(bar.token, WorkDoneProgressReport(false, msg, pct)))
                end
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
