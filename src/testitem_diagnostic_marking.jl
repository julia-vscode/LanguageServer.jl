# Debounce tuning for the workspace publish sweep. `Ref`s (not `const` values)
# so tests can shrink the delays. A mutation schedules the sweep
# `SWEEP_DEBOUNCE_SECONDS` after the *last* mutation, but at most
# `SWEEP_MAX_LATENCY_SECONDS` after the *first* unpublished one, so cross-file
# feedback keeps flowing during continuous typing.
const SWEEP_DEBOUNCE_SECONDS = Ref(0.4)
const SWEEP_MAX_LATENCY_SECONDS = Ref(3.0)

"""
    schedule_publish_sweep!(server)

Mark the workspace dirty and (re)arm the debounce timer for the publish sweep.
Every call supersedes previously scheduled sweeps (the generation counter makes
their queued messages stale), so a burst of mutations results in a single
sweep. Must be called from the dispatch task; the timer callback only ever
touches the (task-safe) message queue.
"""
function schedule_publish_sweep!(server)
    if !server._sweep_pending
        server._sweep_pending = true
        server._sweep_first_dirty_time = time()
    end

    server._sweep_generation += 1
    generation = server._sweep_generation

    if server._sweep_timer !== nothing
        close(server._sweep_timer)
        server._sweep_timer = nothing
    end

    if time() - server._sweep_first_dirty_time >= SWEEP_MAX_LATENCY_SECONDS[]
        put!(server.combined_msg_queue, (type=:publish_sweep, generation=generation))
        return
    end

    server._sweep_timer = Timer(SWEEP_DEBOUNCE_SECONDS[]) do _
        try
            put!(server.combined_msg_queue, (type=:publish_sweep, generation=generation))
        catch
            # The queue is closed during shutdown; nothing left to publish.
        end
    end

    return
end

"""
    handle_publish_sweep_msg!(server, generation)

Dispatch-loop handler for `:publish_sweep` messages. Messages from superseded
schedules are ignored. When other messages are already queued (e.g. interactive
requests) and the max-latency budget has not run out, the sweep re-enqueues
itself behind them instead of blocking the queue.
"""
function handle_publish_sweep_msg!(server, generation)
    server._sweep_pending || return
    generation == server._sweep_generation || return

    if isready(server.combined_msg_queue) && time() - server._sweep_first_dirty_time < SWEEP_MAX_LATENCY_SECONDS[]
        put!(server.combined_msg_queue, (type=:publish_sweep, generation=generation))
        return
    end

    server._sweep_pending = false
    server._sweep_timer = nothing
    run_publish_sweep(server)

    return
end

"""
    run_publish_sweep(server)

Bring the whole workspace's published diagnostics and testitems up to date:
compute current per-file hashes, diff them against `server._published_hashes`
(what the client last received), publish only the differences, and record the
new state. This is the one place the full workspace lint is pulled, so it also
serves as the consistency point after mutations.
"""
function run_publish_sweep(server)
    server.workspace === nothing && return

    new_ti = Dict{URI,UInt}(k => hash(v) for (k, v) in JuliaWorkspaces.get_test_items(server.workspace))
    new_diag = Dict{URI,UInt}(k => hash(v) for (k, v) in JuliaWorkspaces.get_diagnostics(server.workspace))

    old = server._published_hashes

    updated_diag = Set{URI}(uri for (uri, h) in new_diag if get(old.diagnostics, uri, nothing) != h)
    deleted_diag = setdiff(Set{URI}(keys(old.diagnostics)), keys(new_diag))
    updated_ti = Set{URI}(uri for (uri, h) in new_ti if get(old.testitems, uri, nothing) != h)
    deleted_ti = setdiff(Set{URI}(keys(old.testitems)), keys(new_ti))

    if !server.clientcapability_workspace_diagnostic_refreshsupport
        publish_diagnostics(server, updated_diag, deleted_diag, URI[])
    end
    publish_tests(server, updated_ti, deleted_ti)

    server._published_hashes = (testitems=new_ti, diagnostics=new_diag)

    reconcile_indirect_file_watchers(server)

    return
end

"""
    publish_file_diagnostics_testitems(server, uris)

Immediately publish diagnostics and testitems for the given files (used for
the file a mutation directly targets, so in-editor feedback does not wait for
the debounced sweep). Publishes only when the file's state differs from what
the client last received, and records the published hashes so the following
sweep does not resend it.
"""
function publish_file_diagnostics_testitems(server, uris::Vector{URI})
    server.workspace === nothing && return

    for uri in uris
        JuliaWorkspaces.has_file(server.workspace, uri) || continue

        diag_hash = hash(JuliaWorkspaces.get_diagnostic(server.workspace, uri))
        if get(server._published_hashes.diagnostics, uri, nothing) != diag_hash
            if !server.clientcapability_workspace_diagnostic_refreshsupport
                publish_diagnostics(server, URI[], URI[], [uri])
            end
            server._published_hashes.diagnostics[uri] = diag_hash
        end

        ti_hash = hash(JuliaWorkspaces.get_test_items(server.workspace, uri))
        if get(server._published_hashes.testitems, uri, nothing) != ti_hash
            publish_tests(server, [uri], URI[])
            server._published_hashes.testitems[uri] = ti_hash
        end
    end

    return
end

function build_lsp_diagnostics(server, uri::URI, jw_diags)
    diags = Diagnostic[]
    if JuliaWorkspaces.has_file(server.workspace, uri)
        st = JuliaWorkspaces.get_text_file(server.workspace, uri).content

        for i in jw_diags
            push!(diags, Diagnostic(
                Range(st, i.range),
                if i.severity==:error
                    DiagnosticSeverities.Error
                elseif i.severity==:warning
                    DiagnosticSeverities.Warning
                elseif i.severity==:information
                    DiagnosticSeverities.Information
                elseif i.severity==:hint
                    DiagnosticSeverities.Hint
                else
                    error("Unknown severity $(i.severity)")
                end,
                missing,
                i.uri === nothing ? missing : CodeDescription(i.uri),
                i.source,
                i.message,
                length(i.tags)==0 ? missing : DiagnosticTag[j==:unnecessary ? DiagnosticTags.Unnecessary : j==:deprecated ? DiagnosticTags.Deprecated : error("Unknown tag $j") for j in i.tags],
                missing
            ))
        end
    end
    return diags
end

function publish_diagnostics(server, jw_diagnostics_updated, jw_diagnostics_deleted, uris::Vector{URI})
    @debug "publish_diagnostics" updated_count=length(jw_diagnostics_updated) deleted_count=length(jw_diagnostics_deleted) uri_count=length(uris)

    all_uris_with_updates = Set{URI}()

    for uri in uris
        push!(all_uris_with_updates, uri)
    end

    for uri in jw_diagnostics_updated
        push!(all_uris_with_updates, uri)
    end

    diagnostics = Dict{URI,Vector{Diagnostic}}()

    for uri in all_uris_with_updates
        is_workspace_file(server, uri) || continue
        new_diags = JuliaWorkspaces.has_file(server.workspace, uri) ?
            JuliaWorkspaces.get_diagnostic(server.workspace, uri) : []
        diagnostics[uri] = build_lsp_diagnostics(server, uri, new_diags)
    end

    for (uri, diags) in diagnostics
        version = get(server._open_file_versions, uri, missing)
        params = PublishDiagnosticsParams(uri, version, diags)
        JSONRPC.send(server.jr_endpoint, textDocument_publishDiagnostics_notification_type, params)
    end
end

function publish_tests(server::LanguageServerInstance, updated_files, deleted_files)
    if !ismissing(server.initialization_options) && get(server.initialization_options, "julialangTestItemIdentification", false)
        for uri in updated_files
            testitems_results = JuliaWorkspaces.get_test_items(server.workspace, uri)
            st = JuliaWorkspaces.get_text_file(server.workspace, uri).content

            testitems = TestItemDetail[
                TestItemDetail(
                    id = i.id,
                    label = i.name,
                    range = Range(st, i.range),
                    code = i.code,
                    codeRange = Range(st, i.code_range),
                    optionDefaultImports = i.option_default_imports,
                    optionTags = string.(i.option_tags),
                    optionSetup = string.(i.option_setup)
                ) for i in testitems_results.testitems
            ]
            testsetups= TestSetupDetail[
                TestSetupDetail(
                    name = string(i.name),
                    kind = string(i.kind),
                    range = Range(st, i.range),
                    code = i.code,
                    codeRange = Range(st, i.code_range)
                ) for i in testitems_results.testsetups
            ]
            testerrors = TestErrorDetail[
                TestErrorDetail(
                    id = te.id,
                    label = te.name,
                    range = Range(st, te.range),
                    error = te.message
                ) for te in testitems_results.testerrors
            ]

            version = get(server._open_file_versions, uri, missing)

            params = PublishTestsParams(
                uri,
                version,
                testitems,
                testsetups,
                testerrors
            )
            JSONRPC.send(server.jr_endpoint, textDocument_publishTests_notification_type, params)
        end

        for uri in deleted_files
            JSONRPC.send(server.jr_endpoint, textDocument_publishTests_notification_type, PublishTestsParams(uri, missing, TestItemDetail[], TestSetupDetail[], TestErrorDetail[]))
        end
    end
end


"""
    reconcile_indirect_file_watchers(server::LanguageServerInstance)

Compares JuliaWorkspaces' current set of indirect files against
`server._watched_indirect_files` and sends `client/registerCapability` for
newly-introduced indirect URIs and `client/unregisterCapability` for URIs
that are no longer indirect (because they were promoted, removed from the
include graph, or deleted on disc). Also performs an initial disc read for
freshly-watched URIs and feeds the content back in via
`set_indirect_file_content!`.
"""
function reconcile_indirect_file_watchers(server::LanguageServerInstance)
    # Capability gate: only proceed if the client supports dynamic registration
    # of `workspace/didChangeWatchedFiles` with relative patterns.
    if ismissing(server.clientCapabilities) ||
        ismissing(server.clientCapabilities.workspace) ||
        ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles) ||
        ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles.dynamicRegistration) ||
        ismissing(server.clientCapabilities.workspace.didChangeWatchedFiles.relativePatternSupport) ||
        !server.clientCapabilities.workspace.didChangeWatchedFiles.dynamicRegistration ||
        !server.clientCapabilities.workspace.didChangeWatchedFiles.relativePatternSupport
        return
    end

    current_indirect = JuliaWorkspaces.get_indirect_files(server.workspace)
    watched = server._watched_indirect_files

    # Unregister watchers for URIs no longer indirect.
    to_unregister = Unregistration[]
    for (uri, id) in collect(watched)
        if !(uri in current_indirect)
            push!(to_unregister, Unregistration(id, "workspace/didChangeWatchedFiles"))
            delete!(watched, uri)
        end
    end
    if !isempty(to_unregister)
        try
            JSONRPC.send(
                server.jr_endpoint,
                client_unregisterCapability_request_type,
                UnregistrationParams(to_unregister)
            )
        catch err
            @error "Failed to send client/unregisterCapability for indirect file watchers" exception=(err, catch_backtrace())
        end
    end

    # Register watchers for newly-discovered indirect URIs.
    for uri in current_indirect
        haskey(watched, uri) && continue
        uri.scheme == "file" || continue

        path = JuliaWorkspaces.URIs2.uri2filepath(uri)
        path === nothing && continue

        dir = dirname(path)
        base = basename(path)

        registration_id = string(uuid4())
        registration = Registration(
            registration_id,
            "workspace/didChangeWatchedFiles",
            DidChangeWatchedFilesRegistrationOptions([
                FileSystemWatcher(
                    RelativePattern(JuliaWorkspaces.URIs2.filepath2uri(dir), base),
                    missing
                )
            ])
        )

        try
            JSONRPC.send(
                server.jr_endpoint,
                client_registerCapability_request_type,
                RegistrationParams([registration])
            )
            watched[uri] = registration_id
        catch err
            @error "Failed to send client/registerCapability for indirect file watcher" uri=uri exception=(err, catch_backtrace())
        end
    end
end
