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
    optionSkip::Union{Bool,String}
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
    packageName::Union{String,Missing}
    packageUri::Union{URI,Missing}
    projectUri::Union{URI,Missing}
    envContentHash::Union{String,Missing}
end

"""
One dynamic work item in a `julia/publishServerStatus` notification. Mirrors
`JuliaWorkspaces.DJPStatusItem`, with symbols stringified for the wire.
"""
struct ServerStatusDJPDetail <: Outbound
    kind::String        # "watch_environment" | "watch_test_environment" | "create_standalone_project" | "resolve_environment"
    path::String
    package::Union{String,Missing}
    status::String      # "queued" | "preparing" | "running" | "refresh_queued" | "refreshing" | "done" | "failed"
    progress::Union{Int,Missing}
    failureMessage::Union{String,Missing}
    alive::Bool
end

struct PublishServerStatusParams <: Outbound
    indexingDone::Bool
    pendingCount::Int
    maxConcurrentDjps::Int
    djps::Vector{ServerStatusDJPDetail}
end

include("messagedefs.jl")
