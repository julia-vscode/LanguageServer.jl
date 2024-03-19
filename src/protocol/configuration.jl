@dict_readable struct WorkspaceFoldersChangeEvent
    added::Vector{WorkspaceFolder}
    removed::Vector{WorkspaceFolder}
end

@dict_readable struct DidChangeWorkspaceFoldersParams
    event::WorkspaceFoldersChangeEvent
end

struct DidChangeConfigurationParams
    settings::Any
    function DidChangeConfigurationParams(d)
        if d isa Dict && length(d) == 1 && haskey(d, "settings")
            new(d["settings"])
        else
            new(d)
        end
    end
end

struct ConfigurationItem <: Outbound
    scopeUri::Union{DocumentUri,Missing}
    section::Union{String,Missing}
end

struct ConfigurationParams <: Outbound
    items::Vector{ConfigurationItem}
end

##############################################################################
# File watching
const FileChangeType = Int
const FileChangeTypes = (Created=1,
    Changed=2,
    Deleted=3)

const WatchKind = Int
const WatchKinds = (Create=1,
    Change=2,
    Delete=4)


@dict_readable struct FileEvent
    uri::DocumentUri
    type::FileChangeType
end

@dict_readable struct DidChangeWatchedFilesParams
    changes::Vector{FileEvent}
end

struct FileSystemWatcher <: Outbound
    globPattern::String
    kind::Union{WatchKind,Missing}
end

struct DidChangeWatchedFilesRegistrationOptions <: Outbound
    watchers::Vector{FileSystemWatcher}
end


##############################################################################
# Registration

struct Registration <: Outbound
    id::String
    method::String
    registerOptions::Union{Any,Missing}
end

struct RegistrationParams <: Outbound
    registrations::Vector{Registration}
end

struct TextDocumentRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
end

struct TextDocumentChangeRegistrationOptions <: Outbound
    documentSelector::DocumentSelector
    syncKind::Int
end

struct TextDocumentSaveRegistrationOptions <: Outbound
    documentSelector::DocumentSelector
    includeText::Union{Bool,Missing}
end

struct Unregistration <: Outbound
    id::String
    method::String
end

struct UnregistrationParams <: Outbound
    unregistrations::Vector{Unregistration}
end


struct StaticRegistrationOptions <: Outbound
    id::Union{String,Missing}
end

##############################################################################
