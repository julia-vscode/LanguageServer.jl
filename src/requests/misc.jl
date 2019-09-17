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
    # path = get(r.params, "path", "")
    # uri = get(r.params, "external", "")
    # if isdir(uri2filepath(path))
    #     for doc in values(server.documents)
    #         uri2 = doc._uri
    #         server.debug_mode && @info "LINT: ignoring $path"
    #         if startswith(uri2, uri)
    #             toggle_file_lint(doc, server)
    #         end
    #     end
    # else
    #     if uri in map(i->i._uri, values(server.documents))
    #         server.debug_mode && @info "LINT: ignoring $path"
    #         doc = server.documents[URI2(uri)]
    #         toggle_file_lint(doc, server)
    #     end
    # end
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
    offset = get_offset(doc, tdpp.position)
    x = getcst(doc)
    loc = 0
    p1, p2, p3 = 1, x.span, x.fullspan
    if x.typ === CSTParser.FileH
        (offset > x.fullspan || x.args === nothing) && return 1, x.span, x.fullspan
        for a in x.args
            if loc <= offset < loc + a.fullspan
                if a.typ === CSTParser.ModuleH
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
                elseif a.typ === CSTParser.TopLevel
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

    response = JSONRPC.Response(r.id, (isempty(doc._content) ? 0 : length(doc._content, 1, max(1, p1)), length(doc._content, 1, p2), length(doc._content, 1, p3)))

    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/activateenvironment")}}, params)
    return params
end

function process(r::JSONRPC.Request{Val{Symbol("julia/activateenvironment")}}, server::LanguageServerInstance)
    _set_worker_env(r.params, server)
end

function _set_worker_env(env_path, server::LanguageServerInstance)
    wid = last(procs())
    server.debug_mode && @info "Activating: ", server.env_path
    @fetchfrom wid SymbolServer.Pkg.activate(env_path)

    server.symbol_server.context = @fetchfrom wid SymbolServer.Pkg.Types.Context()
    server.debug_mode && @info "New project file: ",  server.symbol_server.context.env.project_file

    missing_pkgs = SymbolServer.disc_load_project(server.symbol_server)
    if isempty(missing_pkgs)
        server.ss_task = nothing
    else
        pkg_uuids = collect(keys(missing_pkgs))
        server.debug_mode && @info "Missing or outdated package caches: ", collect(missing_pkgs)
        server.ss_task = @spawnat wid SymbolServer.cache_packages_and_save(server.symbol_server.context, pkg_uuids)
    end
end
        