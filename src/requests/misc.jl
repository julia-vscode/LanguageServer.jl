function setTrace_notification(params::SetTraceParams, server::LanguageServerInstance, conn)
end

# TODO Provide type for params
function setTraceNotification_notification(params, server::LanguageServerInstance, conn)
end

function julia_getCurrentBlockRange_request(tdpp::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    fallback = (Position(0, 0), Position(0, 0), tdpp.position)
    uri = tdpp.textDocument.uri

    JuliaWorkspaces.has_file(server.workspace, uri) || return nodocument_error(uri, "getCurrentBlockRange")

    st = jw_source_text(server, uri)

    if jw_version(server, uri) !== tdpp.version
        return mismatched_version_error(uri, jw_version(server, uri), tdpp, "getCurrentBlockRange")
    end

    index = index_at(st, tdpp.position)
    result = JuliaWorkspaces.get_current_block_range(server.workspace, uri, index)
    result === nothing && return fallback

    return (
        jw_position_to_lsp(server, uri, result.highlight_start),
        jw_position_to_lsp(server, uri, result.highlight_stop),
        jw_position_to_lsp(server, uri, result.block_stop)
    )
end

function julia_activateenvironment_notification(params::NamedTuple{(:envPath,),Tuple{String}}, server::LanguageServerInstance, conn)
    if server.env_path != params.envPath
        server.env_path = params.envPath

        empty!(server._extra_tracked_files)

        track_project_files!(server)

        JuliaWorkspaces.set_input_fallback_test_project!(server.workspace.runtime, isempty(server.env_path) ? nothing : filepath2uri(server.env_path))

        # We call this here to remove project and manifest files that were not in the workspace
        gc_files_from_workspace(server)
    end
end

function track_project_files!(server::LanguageServerInstance)
    # Add project files separately in case they are not in a workspace folder
    if server.env_path != ""
        # Base project files
        project_files = [
            "Project.toml",
            "JuliaProject.toml",
            "Manifest.toml",
            "JuliaManifest.toml",
            "Manifest-v$(VERSION.major).$(VERSION.minor).toml",
            "JuliaManifest-v$(VERSION.major).$(VERSION.minor).toml"
        ]

        for file in project_files
            file_full_path = joinpath(server.env_path, file)

            if isfile(file_full_path)
                uri = filepath2uri(file_full_path)
                @static if Sys.iswindows()
                    # Normalize drive letter to lowercase
                    if length(file_full_path) > 1 && isletter(file_full_path[1]) && file_full_path[2] == ':'
                        file_full_path = lowercasefirst(file_full_path)
                    end
                end
                # Only add again if outside of the workspace folders
                if all(i->!startswith(file_full_path, i), server.workspaceFolders)
                    if haskey(server._files_from_disc, uri)
                        error("This should not happen")
                    end

                    text_file = JuliaWorkspaces.read_text_file_from_uri(uri, return_nothing_on_io_error=true)
                    text_file === nothing && continue

                    server._files_from_disc[uri] = text_file

                    if !haskey(server._open_file_versions, uri)
                        JuliaWorkspaces.add_file!(server.workspace, text_file)
                    end
                end
                # But we do want to track, in case the workspace folder is removed
                push!(server._extra_tracked_files, filepath2uri(file_full_path))
            end
        end
    end
end

julia_refreshLanguageServer_notification(_, server::LanguageServerInstance, conn) = nothing

function textDocument_documentLink_request(params::DocumentLinkParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    results = JuliaWorkspaces.get_document_links(server.workspace, uri)

    return map(results) do r
        DocumentLink(jw_range(server, uri, r.start, r.stop), r.target_uri, missing, missing)
    end
end
