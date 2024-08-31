# Julia-specific extensions to the LSP

@dict_readable struct VersionedTextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    version::Int
    position::Position
end

@dict_readable struct TestItemDetail <: Outbound
    id::String
    label::String
    range::Range
    code::String
    codeRange::Range
    optionDefaultImports::Bool
    optionTags::Vector{String}
    optionSetup::Vector{String}
end

@dict_readable struct TestSetupDetail <: Outbound
    name::String
    kind::String
    range::Range
    code::String
    codeRange::Range
end

@dict_readable struct TestErrorDetail <: Outbound
    id::String
    label::String
    range::Range
    error::String
end

struct PublishTestsParams <: Outbound
    uri::DocumentUri
    version::Union{Int,Missing}
    testItemDetails::Vector{TestItemDetail}
    testSetupDetails::Vector{TestSetupDetail}
    testErrorDetails::Vector{TestErrorDetail}
end

@dict_readable struct GetTestEnvRequestParams <: Outbound
    uri::URI
end

@dict_readable struct GetTestEnvRequestParamsReturn <: Outbound
    packageName::String
    packageUri::Union{URI,Missing}
    projectUri::Union{URI,Missing}
    envContentHash::Union{UInt,Missing}
end

include("messagedefs.jl")
