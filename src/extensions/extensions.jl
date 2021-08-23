# Julia-specific extensions to the LSP

@dict_readable struct VersionedTextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    version::Int
    position::Position
end

include("messagedefs.jl")
