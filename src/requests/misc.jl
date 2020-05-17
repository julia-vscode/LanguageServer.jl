function cancel_notification(conn, params::CancelParams, server)
end

function setTraceNotification_notification(conn, params, server)
end

function julia_getCurrentBlockRange_request(conn, params::TextDocumentPositionParams, server)
    tdpp = params
    doc = getdocument(server, URI2(tdpp.textDocument.uri))
    offset = get_offset(doc, tdpp.position)
    x = getcst(doc)
    loc = 0
    p1, p2, p3 = 0, x.span, x.fullspan
    if typof(x) === CSTParser.FileH
        (offset > x.fullspan || x.args === nothing) && return Position(get_position_at(doc, p1)...), Position(get_position_at(doc, p2)...), Position(get_position_at(doc, p3)...)
        for a in x.args
            if loc <= offset < loc + a.fullspan
                if typof(a) === CSTParser.ModuleH
                    if loc + a.args[1].fullspan + a.args[2].fullspan < offset < loc + a.args[1].fullspan + a.args[2].fullspan + a.args[3].fullspan
                        loc0 = loc +  a.args[1].fullspan + a.args[2].fullspan
                        loc += a.args[1].fullspan + a.args[2].fullspan
                        for b in a.args[3].args
                            if loc <= offset < loc + b.fullspan
                                p1, p2, p3 = loc, loc + b.span, loc + b.fullspan
                                break
                            end
                            loc += b.fullspan
                        end
                    else
                        p1, p2, p3 = loc, loc + a.span, loc + a.fullspan
                    end
                elseif typof(a) === CSTParser.TopLevel
                    p1, p2, p3 = loc, loc + a.span, loc + a.fullspan
                    for b in a.args
                        if loc <= offset < loc + b.fullspan
                            p1, p2, p3 = loc, loc + b.span, loc + b.fullspan
                        end
                        loc += b.fullspan
                    end
                else
                    p1, p2, p3 = loc, loc + a.span, loc + a.fullspan
                end
            end
            loc += a.fullspan
        end
    end
    return Position(get_position_at(doc, p1)...), Position(get_position_at(doc, p2)...), Position(get_position_at(doc, p3)...)
end

function julia_activateenvironment_notification(conn, params::String, server)
    server.env_path = params

    trigger_symbolstore_reload(server)
end
