function mark_current_diagnostics_testitems(jw::JuliaWorkspace)
    ti_results = Dict{URI,UInt}(k => hash(v) for (k,v) in JuliaWorkspaces.get_test_items(jw))

    diag_results = Dict{URI,UInt}(k => hash(v) for (k,v) in JuliaWorkspaces.get_diagnostics(jw))

    return (testitems=ti_results, diagnostics=diag_results)
end

function get_files_with_updated_diagnostics_testitems(jw::JuliaWorkspace, old_marked_versions::@NamedTuple{testitems::Dict{URI,UInt},diagnostics::Dict{URI,UInt}})
    # Testitems
    new_marked_versions_ti = Dict{URI,UInt}(k => hash(v) for (k,v) in JuliaWorkspaces.get_test_items(jw))

    old_text_files_ti = Set{URI}(keys(old_marked_versions.testitems))
    new_text_files_ti = Set{URI}(keys(new_marked_versions_ti))

    deleted_files_ti = setdiff(old_text_files_ti, new_text_files_ti)
    updated_files_ti = Set{URI}()

    for (uri,hash_value) in new_marked_versions_ti
        if !(uri in old_text_files_ti)
            push!(updated_files_ti, uri)
        else
            if hash_value != old_marked_versions.testitems[uri]
                push!(updated_files_ti, uri)
            end
        end
    end

    # Diagnostics
    new_marked_versions_diag = Dict{URI,UInt}(k => hash(v) for (k,v) in JuliaWorkspaces.get_diagnostics(jw))

    old_text_files_diag = Set{URI}(keys(old_marked_versions.diagnostics))
    new_text_files_diag = Set{URI}(keys(new_marked_versions_diag))

    deleted_files_diag = setdiff(old_text_files_diag, new_text_files_diag)
    updated_files_diag = Set{URI}()

    for (uri,hash_value) in new_marked_versions_diag
        if !(uri in old_text_files_diag)
            push!(updated_files_diag, uri)
        else
            if hash_value != old_marked_versions.diagnostics[uri]
                push!(updated_files_diag, uri)
            end
        end
    end

    return (;updated_files_ti, deleted_files_ti, updated_files_diag, deleted_files_diag)
end

function publish_diagnostics(server, jw_diagnostics_updated, jw_diagnostics_deleted, uris::Vector{URI})
    all_uris_with_updates = Set{URI}()

    for uri in uris
        push!(all_uris_with_updates, uri)
    end

    for uri in jw_diagnostics_updated
        push!(all_uris_with_updates, uri)
    end

    # Check if a JW diagnostic depends on environment data (matching the old is_diag_dependent_on_env logic)
    function _is_jw_diag_dependent_on_env(d::JuliaWorkspaces.Diagnostic)
        d.source != "StaticLint.jl" && return false
        startswith(d.message, "Missing reference:") && return true
        startswith(d.message, "Possible method call error") && return true
        startswith(d.message, "An imported") && return true
        return false
    end

    diagnostics = Dict{URI,Vector{Diagnostic}}()

    for uri in all_uris_with_updates
        diags = Diagnostic[]
        diagnostics[uri] = diags

        if JuliaWorkspaces.has_file(server.workspace, uri)
            # Check if linting is disabled for this file's directory
            filepath = something(uri2filepath(uri), "")
            skip_env_diags = !isempty(filepath) && any(is_in_target_dir_of_package.(Ref(filepath), server.lint_disableddirs))

            st = JuliaWorkspaces.get_text_file(server.workspace, uri).content

            new_diags = JuliaWorkspaces.get_diagnostic(server.workspace, uri)

            for i in new_diags
                # Skip env-dependent diagnostics from disabled directories
                if skip_env_diags && _is_jw_diag_dependent_on_env(i)
                    continue
                end
                # Respect the runlinter flag for StaticLint diagnostics
                if !server.runlinter && i.source == "StaticLint.jl"
                    continue
                end

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
    end

    for (uri,diags) in diagnostics
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


function publish_diagnostics_testitems(server, marked_versions, uris::Vector{URI})
    updated_files = get_files_with_updated_diagnostics_testitems(server.workspace, marked_versions)

    publish_diagnostics(server, updated_files.updated_files_diag, updated_files.deleted_files_diag, uris)
    publish_tests(server, updated_files.updated_files_ti, updated_files.deleted_files_ti)
end
