function JSONRPC.parse_params(::Type{Val{Symbol("\$/cancelRequest")}}, params)
    return CancelParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/cancelRequest")},CancelParams}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("\$/setTraceNotification")}}, params)
    return Any(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/setTraceNotification")},Dict{String,Any}}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("julia/lint-package")}}, params)
    return 
end

function process(r::JSONRPC.Request{Val{Symbol("julia/lint-package")},Nothing}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggle-lint")}}, params)
    return TextDocumentIdentifier(params["textDocument"])
end

function process(r::JSONRPC.Request{Val{Symbol("julia/toggle-lint")},TextDocumentIdentifier}, server)
    doc = server.documents[URI2(r.uri)]
    doc._runlinter = !doc._runlinter
end


function JSONRPC.parse_params(::Type{Val{Symbol("julia/reload-modules")}}, params)
end

function process(r::JSONRPC.Request{Val{Symbol("julia/reload-modules")},Nothing}, server)
    reloaded = String[]
    failedtoreload = String[]
    for m in names(Main)
        if isdefined(Main, m) && getfield(Main, m) isa Module
            M = getfield(Main, m)
            if !(m in [:Base, :Core, :Main])
                try
                    reload(string(m))
                    push!(reloaded, string(m))
                catch e
                    push!(failedtoreload, string(m))
                end
            end
        end
    end
    
    response = JSONRPC.Notification{Val{Symbol("window/showMessage")},ShowMessageParams}(ShowMessageParams(3, "Julia: Reloaded modules."))
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggleFileLint")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("julia/toggleFileLint")}}, server)
    path = r.params["path"]
    uri = r.params["external"]
    if isdir(uri2filepath(path))
        for doc in values(server.documents)
            uri2 = doc._uri
            server.debug_mode && info("LINT: ignoring $path")
            if startswith(uri2, uri)
                toggle_file_lint(doc, server)
            end
        end
    else
        if uri in map(i->i._uri, values(server.documents))
            server.debug_mode && info("LINT: ignoring $path")
            doc = server.documents[URI2(uri)]
            toggle_file_lint(doc, server)
        end
    end
end



function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggle-log")}}, params)
end

function process(r::JSONRPC.Request{Val{Symbol("julia/toggle-log")},Nothing}, server)
    server.debug_mode = !server.debug_mode
end


function JSONRPC.parse_params(::Type{Val{Symbol("julia/getCurrentBlockOffsetRange")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("julia/getCurrentBlockOffsetRange")}}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end 
    tdpp = r.params
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    i = p1 = p2 = p3 = 0
    for x in doc.code.ast.args
        if i < offset <= i + x.fullspan
            p1, p2, p3 = i, i + length(x.span), i + x.fullspan
            break
        end
        i += x.fullspan
    end
    y, s = scope(doc, offset, server);
    if length(s.stack) > 2 && s.stack[2] isa EXPR{CSTParser.ModuleH}
        i += s.stack[2].args[1].fullspan + s.stack[2].args[2].fullspan
        for x in s.stack[3].args 
            i += x.fullspan
            if x == s.stack[4] 
                p1, p2, p3 = i - x.fullspan, i - x.fullspan + length(x.span), i 
                break
            end
        end
    end
    response = JSONRPC.Response(get(r.id), (ind2chr(doc._content, max(1, p1)), ind2chr(doc._content, p2), ind2chr(doc._content, p3)))
    
    send(response, server)
end
