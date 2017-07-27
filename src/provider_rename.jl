function process(r::JSONRPC.Request{Val{Symbol("textDocument/rename")},RenameParams}, server)
    if !haskey(server.documents, r.params.textDocument.uri)
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    rp = r.params
    uri = rp.textDocument.uri
    doc = server.documents[uri]

    offset = get_offset(doc, rp.position.line + 1, rp.position.character)
    
    y, s, modules, current_namespace = scope(doc, offset, server)
    
    locations = Location[]
    if y isa EXPR{CSTParser.IDENTIFIER}
        id_length = length(y.val)
        id = string(Expr(y))
        ns_name = make_name(s.namespace, Expr(y))
        if haskey(s.symbols, ns_name)
            var_def = last(s.symbols[ns_name])

            rootfile = last(findtopfile(uri, server)[1])

            s = TopLevelScope(ScopePosition(uri, typemax(Int)), ScopePosition(rootfile, 0), false, Dict(), EXPR[], Symbol[], true, true, Dict("toplevel" => []), [])
            toplevel(server.documents[rootfile].code.ast, s, server)
            s.current.offset = 0
            L = LintState(true, [], [], [])
            R = RefState(ns_name, var_def, [])
            references(server.documents[rootfile].code.ast, s, L, R, server, true)
            for (loc, uri1) in R.refs
                doc1 = server.documents[uri1]
                
                loc1 = loc + (0:id_length)
                push!(locations, Location(uri1, Range(doc1, loc1)))
            end
        end
    end

    tdes = Dict{String,TextDocumentEdit}()
    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, rp.newName))
        else
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, server.documents[loc.uri]._version), [TextEdit(loc.range, rp.newName)])
        end
    end

    we = WorkspaceEdit(nothing, collect(values(tdes)))
    response = JSONRPC.Response(get(r.id), we)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/rename")}}, params)
    return RenameParams(params)
end

