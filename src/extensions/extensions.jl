# Julia-specific extensions to the LSP

@dict_readable struct VersionedTextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    version::Int
    position::Position
end

@dict_readable struct TestItemDetail <: Outbound
    id::String
    label::String
    project_uri::Union{URI,Nothing}
    package_uri::Union{URI,Nothing}
    package_name::String
    range::Range
    code::Union{Nothing,String}
    code_range::Union{Nothing,Range}
    option_default_imports::Union{Nothing,Bool}
    option_tags::Union{Nothing,Vector{String}}
end

@dict_readable struct TestSetupDetail <: Outbound
    name::String
    package_uri::Union{URI,Nothing}
    package_name::String
    range::Range
    code::Union{Nothing,String}
    code_range::Union{Nothing,Range}
end

@dict_readable struct TestErrorDetail <: Outbound
    range::Range
    error::String
end

struct PublishTestsParams <: Outbound
    uri::DocumentUri
    version::Union{Int,Missing}
    testitemdetails::Vector{TestItemDetail}
    testsetupdetails::Vector{TestSetupDetail}
    testerrordetails::Vector{TestErrorDetail}
end

include("messagedefs.jl")
