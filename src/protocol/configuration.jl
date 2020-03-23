@dict_readable struct WorkspaceFoldersChangeEvent
    added::Vector{WorkspaceFolder}
    removed::Vector{WorkspaceFolder}
end

@dict_readable struct DidChangeWorkspaceFoldersParams
    event::WorkspaceFoldersChangeEvent
end

@dict_readable struct DidChangeConfigurationParams
    settings::Any
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
const FileChangeTypes = Dict("Created" => 1, "Changed" => 2, "Deleted" => 3)
@dict_readable struct FileEvent
    uri::String
    type::FileChangeType
end

@dict_readable struct DidChangeWatchedFilesParams
    changes::Vector{FileEvent}
end

const WatchKind = Int
const WatchKinds = Dict("Create" => 1,
                       "Change" => 2,
                       "Delete" => 4)
struct FileSystemWatcher <: Outbound
    globPattern::String
    kind::Union{WatchKind,Missing}
end

struct DidChangeWatchedFilesRegistrationOptions <: Outbound
    watchers::Vector{FileSystemWatcher}
end

##############################################################################


struct CreateFileOptions <: Outbound
    overwrite::Union{Bool,Missing}
    ignoreIfExists::Union{Bool,Missing}
end

struct CreateFile <: Outbound
    kind::String
    uri::DocumentUri
    options::Union{CreateFileOptions,Missing}
    CreateFile(uri, options = missing) = new("create", uri, options)
end

struct RenameFileOptions <: Outbound
    overwrite::Union{Bool,Missing}
    ignoreIfExists::Union{Bool,Missing}
end

struct RenameFile <: Outbound
    kind::String
    oldUri::DocumentUri
    newUri::DocumentUri
    options::Union{RenameFileOptions,Missing}
    RenameFile(uri, options = missing) = new("rename", uri, options)
end

struct DeleteFileOptions <: Outbound
    overwrite::Union{Bool,Missing}
    ignoreIfNotExists::Union{Bool,Missing}
end

struct DeleteFile <: Outbound
    kind::String
    uri::DocumentUri
    options::Union{DeleteFileOptions,Missing}
    DeleteFile(uri, options = missing) = new("delete", uri, options)
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
