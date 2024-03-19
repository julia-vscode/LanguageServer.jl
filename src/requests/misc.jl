function cancel_notification(params::CancelParams, server::LanguageServerInstance, conn)
end

function setTrace_notification(params::SetTraceParams, server::LanguageServerInstance, conn)
end

# TODO Provide type for params
function setTraceNotification_notification(params, server::LanguageServerInstance, conn)
end

function julia_getCurrentBlockRange_request(tdpp::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    fallback = (Position(0, 0), Position(0, 0), tdpp.position)
    uri = tdpp.textDocument.uri

    hasdocument(server, uri) || return nodocument_error(uri)

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
                            a = x[i+1]
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

        files_to_check = [joinpath(server.env_path, "Project.toml"), joinpath(server.env_path, "JuliaProject.toml"), joinpath(server.env_path, "Manifest.toml"), joinpath(server.env_path, "JuliaManifest.toml")]

        for file_to_check in files_to_check
            if isfile(file_to_check)
                server.workspace = add_file(server.workspace, filepath2uri(file_to_check))
            end
        end

        trigger_symbolstore_reload(server)
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
