function process(r::JSONRPC.Request{Val{Symbol("textDocument/rename")},RenameParams}, server)
    if !haskey(server.documents, filepath_from_uri(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    rp = r.params
    uri = rp.textDocument.uri
    doc = server.documents[filepath_from_uri(uri)]
    offset = get_offset(doc, rp.position.line + 1, rp.position.character)
    
    locations = references(doc, offset, server)

    tdes = Dict{String,TextDocumentEdit}()
    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, rp.newName))
        else
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, server.documents[filepath_from_uri(loc.uri)]._version), [TextEdit(loc.range, rp.newName)])
        end
    end

    we = WorkspaceEdit(nothing, collect(values(tdes)))
    response = JSONRPC.Response(get(r.id), we)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/rename")}}, params)
    return RenameParams(params)
end

