JSONRPC.parse_params(::Type{Val{Symbol("\$/cancelRequest")}}, params) = CancelParams(params)
function process(r::JSONRPC.Request{Val{Symbol("\$/cancelRequest")},CancelParams}, server) end

JSONRPC.parse_params(::Type{Val{Symbol("\$/setTraceNotification")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("\$/setTraceNotification")},Dict{String,Any}}, server) end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/lint-package")}}, params) end
function process(r::JSONRPC.Request{Val{Symbol("julia/lint-package")},Nothing}, server) end

JSONRPC.parse_params(::Type{Val{Symbol("julia/toggle-lint")}}, params) = TextDocumentIdentifier(params["textDocument"])
function process(r::JSONRPC.Request{Val{Symbol("julia/toggle-lint")},TextDocumentIdentifier}, server)
    doc = server.documents[URI2(r.uri)]
    doc._runlinter = !doc._runlinter
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/reload-modules")}}, params) end
function process(r::JSONRPC.Request{Val{Symbol("julia/reload-modules")},Nothing}, server) end

JSONRPC.parse_params(::Type{Val{Symbol("julia/toggleFileLint")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("julia/toggleFileLint")}}, server) end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggle-log")}}, params) end
function process(r::JSONRPC.Request{Val{Symbol("julia/toggle-log")},Nothing}, server)
    server.debug_mode = !server.debug_mode
end


JSONRPC.parse_params(::Type{Val{Symbol("julia/getCurrentBlockOffsetRange")}}, params) = TextDocumentPositionParams(params)
function process(r::JSONRPC.Request{Val{Symbol("julia/getCurrentBlockOffsetRange")}}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'julia/getCurrentBlockOffsetRange for non-existing document.")
    end
    tdpp = r.params
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    offset = get_offset(doc, tdpp.position)
    x = getcst(doc)
    loc = 0
    p1, p2, p3 = 1, x.span, x.fullspan
    if typof(x) === CSTParser.FileH
        (offset > x.fullspan || x.args === nothing) && return 1, x.span, x.fullspan
        for a in x.args
            if loc <= offset < loc + a.fullspan
                if typof(a) === CSTParser.ModuleH
                    if loc + a.args[1].fullspan + a.args[2].fullspan < offset < loc + a.args[1].fullspan + a.args[2].fullspan + a.args[3].fullspan
                        loc0 = loc +  a.args[1].fullspan + a.args[2].fullspan
                        loc += a.args[1].fullspan + a.args[2].fullspan
                        for b in a.args[3].args
                            if loc <= offset < loc + b.fullspan
                                p1, p2, p3 = loc + 1, loc + b.span, loc + b.fullspan
                                break
                            end
                            loc += b.fullspan
                        end
                    else
                        p1, p2, p3 = loc + 1, loc + a.span, loc + a.fullspan
                    end
                elseif typof(a) === CSTParser.TopLevel
                    p1, p2, p3 = loc + 1, loc + a.span, loc + a.fullspan
                    for b in a.args
                        if loc <= offset < loc + b.fullspan
                            p1, p2, p3 = loc + 1, loc + b.span, loc + b.fullspan
                        end
                        loc += b.fullspan
                    end
                else
                    p1, p2, p3 = loc + 1, loc + a.span, loc + a.fullspan
                end
            end
            loc += a.fullspan
        end
    end
    # p1 : byte position of start of expression
    # p2 : byte position of end of expression
    # p3 : byte position of end of trailing whitespace of expression
    return (isempty(get_text(doc)) ? 0 : length(get_text(doc), 1, max(1, p1)), length(get_text(doc), 1, p3), length(get_text(doc), 1, p3))
end

JSONRPC.parse_params(::Type{Val{Symbol("julia/activateenvironment")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("julia/activateenvironment")}}, server)
    server.env_path = r.params

    trigger_symbolstore_reload(server)
end
