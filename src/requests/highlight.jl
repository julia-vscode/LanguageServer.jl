# NOTE: 3.15 LSP features
const ProgressToken = Union{Int,String}

@dict_readable struct DocumentHighlightParams
    textDocument::TextDocumentIdentifier
    position::Position
    # workDoneToken::Union{Missing,ProgressToken}
    # partialResultToken::Union{Missing,ProgressToken}
end

JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentHighlight")}}, params) = DocumentHighlightParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentHighlight")},DocumentHighlightParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/documentHighlight for non-existing document.")
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    p1, p2, p3 = process(JSONRPC.Request{Val{Symbol("julia/getCurrentBlockRange")}, TextDocumentPositionParams}(0, TextDocumentPositionParams(r.params.textDocument, r.params.position)), server)
    rng = Range(p1, p2)
    return DocumentHighlight[DocumentHighlight(rng , DocumentHighlightKinds["Write"])]
end