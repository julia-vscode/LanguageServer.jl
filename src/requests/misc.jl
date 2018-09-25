function JSONRPC.parse_params(::Type{Val{Symbol("\$/cancelRequest")}}, params)
    return CancelParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("\$/cancelRequest")},CancelParams}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("\$/setTraceNotification")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("\$/setTraceNotification")},Dict{String,Any}}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("julia/lint-package")}}, params)
    return 
end

function process(r::JSONRPC.Request{Val{Symbol("julia/lint-package")},Nothing}, server)
    for (uri, f) in server.documents
        @info basename(uri._uri), " ", f.code.index
    end
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
            server.debug_mode && @info "LINT: ignoring $path"
            if startswith(uri2, uri)
                toggle_file_lint(doc, server)
            end
        end
    else
        if uri in map(i->i._uri, values(server.documents))
            server.debug_mode && @info "LINT: ignoring $path"
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
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end 
    tdpp = r.params
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)
    if length(stack) > 1 && stack[1] isa CSTParser.EXPR{CSTParser.FileH}
        if stack[2] isa  CSTParser.EXPR{CSTParser.ModuleH} && length(stack) > 3
            p1, p2, p3 = (offsets[4] + 1, offsets[4] + last(stack[4].span), offsets[4] + stack[4].fullspan)
        else
            p1, p2, p3 = (offsets[2] + 1, offsets[2] + last(stack[2].span), offsets[2] + stack[2].fullspan)
        end
    else 
        p1 = p2 = p3 = length(doc._content)
    end
    
    response = JSONRPC.Response(r.id, (length(doc._content, 1, max(1, p1)), length(doc._content, 1, p2), length(doc._content, 1, p3)))
    
    send(response, server)
end
