function cancel_notification(params::CancelParams, server::LanguageServerInstance, conn)
end

# TODO Provide type for params
function setTraceNotification_notification(params, server::LanguageServerInstance, conn)
end

function julia_getCurrentBlockRange_request(tdpp::VersionedTextDocumentPositionParams, server::LanguageServerInstance, conn)
    fallback = (Position(0, 0), Position(0, 0), tdpp.position)
    uri = URI2(tdpp.textDocument.uri)

    hasdocument(server, uri) || return nodocuemnt_error(uri)

    doc = getdocument(server, uri)

    if doc._version !== tdpp.version
        return mismatched_version_error(uri, doc, tdpp, "getCurrentBlockRange")
    end

    offset = get_offset(doc, tdpp.position)
    x = getcst(doc)
    loc = 0

    if typof(x) === CSTParser.FileH
        for a in x.args
            if loc <= offset <= loc + a.span
                if CSTParser.defines_module(a) # Within module at the top-level, lets see if we can select on of the block arguments
                    if loc <= offset <= loc + a.args[1].span # Within `module` keyword, so return entire expression
                        return Position(get_position_at(doc, loc)...), Position(get_position_at(doc, loc + a.span)...), Position(get_position_at(doc, loc + a.fullspan)...)
                    end
                    if loc + a.args[1].fullspan <= offset <= loc + a.args[1].fullspan + a.args[2].span # Within name of the module, so return entire expression
                        return Position(get_position_at(doc, loc)...), Position(get_position_at(doc, loc + a.span)...), Position(get_position_at(doc, loc + a.fullspan)...)
                    end

                    if loc + a.args[1].fullspan + a.args[2].fullspan <= offset <= loc + a.args[1].fullspan + a.args[2].fullspan + a.args[3].span # Within the body of a module
                        loc += a.args[1].fullspan + a.args[2].fullspan
                        for b in a.args[3].args
                            if loc <= offset <= loc + b.span
                                return Position(get_position_at(doc, loc)...), Position(get_position_at(doc, loc + b.span)...), Position(get_position_at(doc, loc + b.fullspan)...)
                            end
                            loc += b.fullspan
                        end
                    elseif loc + a.args[1].fullspan + a.args[2].fullspan + a.args[3].fullspan < offset < loc + a.args[1].fullspan + a.args[2].fullspan + a.args[3].fullspan + a.args[4].span # Within `end` of the module, so return entire expression
                        return Position(get_position_at(doc, loc)...), Position(get_position_at(doc, loc + a.span)...), Position(get_position_at(doc, loc + a.fullspan)...)
                    end
                elseif typof(a) === CSTParser.TopLevel
                    for b in a.args
                        if loc <= offset <= loc + b.span
                            return Position(get_position_at(doc, loc)...), Position(get_position_at(doc, loc + b.span)...), Position(get_position_at(doc, loc + b.fullspan)...)
                        end
                        loc += b.fullspan
                    end
                else
                    return Position(get_position_at(doc, loc)...), Position(get_position_at(doc, loc + a.span)...), Position(get_position_at(doc, loc + a.fullspan)...)
                end
            end
            loc += a.fullspan
        end
    end
    return fallback
end

function julia_activateenvironment_notification(params::String, server::LanguageServerInstance, conn)
    server.env_path = params

    trigger_symbolstore_reload(server)
end

julia_refreshLanguageServer_notification(_, server::LanguageServerInstance, conn) =
    trigger_symbolstore_reload(server)
