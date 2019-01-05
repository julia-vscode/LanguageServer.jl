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
    path = get(r.params, "path", "")
    uri = get(r.params, "external", "")
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

"""
    eval_descend_stack(stack, offsets, offset)

Descends through the stack such that it always returns block arguments of 
toplevel,function,macro,while,for and let expressions.
"""
function eval_descend_stack(stack, offsets, offset)
    length(stack) == 1 && return first(stack), first(offsets)
    if length(stack) > 1
        if first(stack) isa CSTParser.EXPR{T} where T <: Union{CSTParser.TopLevel,CSTParser.FileH,CSTParser.Block}
            popfirst!(stack)
            popfirst!(offsets)
            return eval_descend_stack(stack, offsets, offset)
        elseif first(stack) isa CSTParser.EXPR{T} where T <: Union{CSTParser.FunctionDef,CSTParser.Macro,CSTParser.While,CSTParser.For,CSTParser.Let} 
            s1 = first(stack)
            o1 = first(offsets)
            if o1 + s1.args[1].fullspan + s1.args[2].span <= offset <= o1 + s1.fullspan - s1.args[4].fullspan
                popfirst!(stack)
                popfirst!(offsets)
                return eval_descend_stack(stack, offsets, offset)
            end
        elseif first(stack) isa CSTParser.EXPR{CSTParser.If}
            s1 = first(stack)
            o1 = first(offsets)
            if length(s1) == 4 # if a end
                if o1 + s1.args[1].fullspan + s1.args[2].span <= offset <= o1 + s1.fullspan - s1.args[4].fullspan
                    popfirst!(stack)
                    popfirst!(offsets)
                    return eval_descend_stack(stack, offsets, offset)
                end
            elseif length(s1) == 6 # if a else end
                if o1 + s1.args[1].fullspan + s1.args[2].span <= offset <= o1 + s1.args[1].fullspan + s1.args[2].fullspan + s1.args[3].fullspan || 
                    o1 + s1.args[1].fullspan + s1.args[2].fullspan + s1.args[3].fullspan + s1.args[4].fullspan <= offset <= o1 + s1.fullspan - s1.args[6].fullspan
                    popfirst!(stack)
                    popfirst!(offsets)
                    return eval_descend_stack(stack, offsets, offset)
                end
            elseif length(s1) == 2 # elseif b (inner branch, no trailing else)
                if o1 + s1.args[1].span <= offset
                    popfirst!(stack)
                    popfirst!(offsets)
                    return eval_descend_stack(stack, offsets, offset)
                end
            end
        end
    end
    return first(stack), first(offsets)
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
    offset = get_offset(doc, tdpp.position.line. tdpp.position.character)
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)
    s,o = eval_descend_stack(stack, offsets, offset)
    p1, p2, p3 = (o + 1, o + s.fullspan, o + s.fullspan)
    response = JSONRPC.Response(r.id, (length(doc._content, 1, max(1, p1)), length(doc._content, 1, p2), length(doc._content, 1, p3)))
    
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/activateenvironment")}}, params)
end

function process(r::JSONRPC.Request{Val{Symbol("julia/activateenvironment")}}, server)
end