function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentLink")},DocumentLinkParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    uri = r.params.textDocument.uri 
    doc = server.documents[URI2(uri)]
    links = Tuple{String,UnitRange{Int}}[]
    # get_links(doc.code.ast, 0, uri, server, links)
    doclinks = DocumentLink[]
    for (uri2, loc) in links
        rng = Range(Position(get_position_at(doc, first(loc))..., one_based = true), Position(get_position_at(doc, last(loc))..., one_based = true))
        push!(doclinks, DocumentLink(rng, uri2))
    end

    response = JSONRPC.Response(get(r.id), links) 
    send(response, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentLink")}}, params)
    return DocumentLinkParams(params) 
end


# function get_links(x, offset::Int, uri::String, server, links) end

# function get_links(x::LITERAL{Tokens.STRING}, offset::Int, uri::String, server, links)
#     if endswith(x.val, ".jl")
#         if !isabspath(x.val)
#             file = joinpath(dirname(uri), x.val)
#         else
#             file = filepath2uri(x.val)
#         end
#         push!(links, (file, offset + (1:x.fullspan)))
#     end
# end

# function get_links(x::EXPR, offset::Int, uri::String, server, links = Tuple{String,UnitRange}[])
#     if CSTParser.no_iter(x)
#         return links
#     end
#     for a in x
#         get_links(a, offset, uri, server, links)
#         offset += a.fullspan
#     end
#     return links
# end
