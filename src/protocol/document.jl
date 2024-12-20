
##############################################################################


struct CreateFileOptions <: Outbound
    overwrite::Union{Bool,Missing}
    ignoreIfExists::Union{Bool,Missing}
end

struct CreateFile <: Outbound
    kind::String
    uri::DocumentUri
    options::Union{CreateFileOptions,Missing}
    CreateFile(uri, options=missing) = new("create", uri, options)
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
    RenameFile(uri, options=missing) = new("rename", uri, options)
end

struct DeleteFileOptions <: Outbound
    recursive::Union{Bool,Missing}
    ignoreIfNotExists::Union{Bool,Missing}
end

struct DeleteFile <: Outbound
    kind::String
    uri::DocumentUri
    options::Union{DeleteFileOptions,Missing}
    DeleteFile(uri, options=missing) = new("delete", uri, options)
end


@dict_readable struct TextDocumentIdentifier
    uri::DocumentUri
end

@dict_readable struct TextDocumentItem
    uri::DocumentUri
    languageId::String
    version::Int
    text::String
end

@dict_readable struct VersionedTextDocumentIdentifier <: Outbound
    uri::DocumentUri
    version::Union{Int,Nothing}
end

@dict_readable struct TextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    position::Position
end

mutable struct TextDocumentEdit
    textDocument::VersionedTextDocumentIdentifier
    edits::Vector{TextEdit}
end

mutable struct WorkspaceEdit <: Outbound
    changes::Union{Any,Missing}
    documentChanges::Union{Vector{TextDocumentEdit},Missing}
    # documentChanges::Union{Vector{TextDocumentEdit},Vector{Union{TextDocumentEdit,CreateFile,RenameFile,DeleteFile}}}
end

@dict_readable struct DidOpenTextDocumentParams
    textDocument::TextDocumentItem
end

@dict_readable struct TextDocumentContentChangeEvent <: Outbound
    range::Union{Range,Missing}
    rangeLength::Union{Int,Missing}
    text::String
end

@dict_readable struct DidChangeTextDocumentParams
    textDocument::VersionedTextDocumentIdentifier
    contentChanges::Vector{TextDocumentContentChangeEvent}
end

@dict_readable struct DidSaveTextDocumentParams <: Outbound
    textDocument::TextDocumentIdentifier
    text::Union{String,Missing}
end

@dict_readable struct DidCloseTextDocumentParams
    textDocument::TextDocumentIdentifier
end

const TextDocumentSaveReason = Int
const TextDocumentSaveReasons = (Manual=1,
    AfterDelay=2,
    FocusOut=3)

@dict_readable struct WillSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
    reason::TextDocumentSaveReason
end
