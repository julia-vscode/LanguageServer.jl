# Julia-specific extensions to the LSP

@dict_readable struct VersionedTextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    version::Int
    position::Position
end

@dict_readable struct Testitem <: Outbound
    name::String
    range::Range
end

struct PublishTestitemsParams <: Outbound
    uri::DocumentUri
    version::Union{Int,Missing}
    testitems::Vector{Testitem}
end

include("messagedefs.jl")
