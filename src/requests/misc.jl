function setTrace_notification(params::SetTraceParams, server::LanguageServerInstance, conn)
end

# TODO Provide type for params
function setTraceNotification_notification(params, server::LanguageServerInstance, conn)
end

function julia_getCurrentBlockRange_request(tdpp::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    fallback = (Position(0, 0), Position(0, 0), tdpp.position)
    uri = tdpp.textDocument.uri

    hasdocument(server, uri) || return nodocument_error(uri, "getCurrentBlockRange")

    doc = getdocument(server, uri)

    if get_version(doc) !== tdpp.version
        return mismatched_version_error(uri, doc, tdpp, "getCurrentBlockRange")
    end

    offset = get_offset(doc, tdpp.position)
    x = getcst(doc)
    loc = 0

    if headof(x) === :file
        for (i, a) in enumerate(x)
            if loc <= offset <= loc + a.fullspan
                # we'll try to use the next expression instead if the current expr is a
                # NOTHING or we're in the whitespace after an expr _and_ that whitespace wraps
                # to a new line
                if !(loc <= offset <= loc + a.span) || headof(a) === :NOTHING
                    if length(x) > i
                        thisline, _ = get_position_from_offset(doc, loc + a.span)
                        if tdpp.position.line > thisline || headof(a) === :NOTHING
                            loc += a.fullspan
                            a = x[i + 1]
                        end
                    end
                end

                if a.head === :macrocall && a.args[1].head === :globalrefdoc && length(a.args) == 4 && CSTParser.defines_module(a.args[4])
                    for i in 1:3
                        loc += a.args[i].fullspan
                    end
                    a = a.args[4]
                end

                if CSTParser.defines_module(a) # Within module at the top-level, lets see if we can select on of the block arguments
                    if loc <= offset <= loc + a.trivia[1].span # Within `module` keyword, so return entire expression
                        return Position(get_position_from_offset(doc, loc)...), Position(get_position_from_offset(doc, loc + a.span)...), Position(get_position_from_offset(doc, loc + a.fullspan)...)
                    end
                    if loc + a.trivia[1].fullspan <= offset <= loc + a.trivia[1].fullspan + a.args[2].span # Within name of the module, so return entire expression
                        return Position(get_position_from_offset(doc, loc)...), Position(get_position_from_offset(doc, loc + a.span)...), Position(get_position_from_offset(doc, loc + a.fullspan)...)
                    end

                    if loc + a.trivia[1].fullspan + a.args[2].fullspan <= offset <= loc + a.trivia[1].fullspan + a.args[2].fullspan + a.args[3].span # Within the body of a module
                        loc += a.trivia[1].fullspan + a.args[2].fullspan
                        for b in a.args[3].args
                            if loc <= offset <= loc + b.span
                                return Position(get_position_from_offset(doc, loc)...), Position(get_position_from_offset(doc, loc + b.span)...), Position(get_position_from_offset(doc, loc + b.fullspan)...)
                            end
                            loc += b.fullspan
                        end
                    elseif loc + a.trivia[1].fullspan + a.args[2].fullspan + a.args[3].fullspan < offset <= loc + a.trivia[1].fullspan + a.args[2].fullspan + a.args[3].fullspan + a.trivia[2].span # Within `end` of the module, so return entire expression
                        return Position(get_position_from_offset(doc, loc)...), Position(get_position_from_offset(doc, loc + a.span)...), Position(get_position_from_offset(doc, loc + a.fullspan)...)
                    end
                else
                    return Position(get_position_from_offset(doc, loc)...), Position(get_position_from_offset(doc, loc + a.span)...), Position(get_position_from_offset(doc, loc + a.fullspan)...)
                end
            end
            loc += a.fullspan
        end
    end
    return fallback
end

function julia_activateenvironment_notification(params::NamedTuple{(:envPath,),Tuple{String}}, server::LanguageServerInstance, conn)
    if server.env_path != params.envPath
        server.env_path = params.envPath

        empty!(server._extra_tracked_files)

        track_project_files!(server)

        JuliaWorkspaces.set_input_fallback_test_project!(server.workspace.runtime, isempty(server.env_path) ? nothing : filepath2uri(server.env_path))

        # We call this here to remove project and manifest files that were not in the workspace
        gc_files_from_workspace(server)

        trigger_symbolstore_reload(server)
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

julia_refreshLanguageServer_notification(_, server::LanguageServerInstance, conn) =
    trigger_symbolstore_reload(server)

function textDocument_documentLink_request(params::DocumentLinkParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    links = DocumentLink[]
    find_document_links(getcst(doc), doc, 0, links)
    return links
end

function find_document_links(x, doc, offset, links)
    if x isa EXPR && CSTParser.isstringliteral(x)
        if valof(x) isa String && isvalid(valof(x)) && sizeof(valof(x)) < 256 # AUDIT: OK
            try
                if isabspath(valof(x)) && safe_isfile(valof(x))
                    path = valof(x)
                    push!(links, DocumentLink(Range(doc, offset .+ (0:x.span)), filepath2uri(path), missing, missing))
                elseif !isempty(getpath(doc)) && safe_isfile(joinpath(_dirname(getpath(doc)), valof(x)))
                    path = joinpath(_dirname(getpath(doc)), valof(x))
                    push!(links, DocumentLink(Range(doc, offset .+ (0:x.span)), filepath2uri(path), missing, missing))
                end
            catch err
                isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
            end
        end
    end
    if x.args !== nothing
        for arg in x
            find_document_links(arg, doc, offset, links)
            offset += arg.fullspan
        end
    end
end
