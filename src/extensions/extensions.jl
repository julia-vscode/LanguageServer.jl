# Julia-specific extensions to the LSP

@dict_readable struct VersionedTextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    version::Int
    position::Position
end

@dict_readable struct Testitem <: Outbound    
    range::Range
    name::Union{Nothing,String}
    code::Union{Nothing,String}
    code_range::Union{Nothing,Range}
    default_imports::Union{Nothing,Bool}
    tags::Union{Nothing,Vector{String}}
    error::Union{Nothing,String}
end

struct PublishTestitemsParams <: Outbound
    uri::DocumentUri
    version::Union{Int,Missing}
    project_path::String
    package_path::String
    package_name::String
    testitems::Vector{Testitem}
end

include("messagedefs.jl")
