@dict_readable struct TextDocumentIdentifier
    uri::DocumentUri
end

@dict_readable struct TextDocumentItem
    uri::DocumentUri
    languageId::String
    version::Int
    text::String
end

@dict_readable struct VersionedTextDocumentIdentifier
    uri::DocumentUri
    version::Union{Int,Nothing}
end

@dict_readable struct TextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    position::Position
end

mutable struct DocumentFilter
    language::Union{String,Missing}
    scheme::Union{String,Missing}
    pattern::Union{String,Missing}
end

const DocumentSelector = Vector{DocumentFilter}

mutable struct TextDocumentEdit
    textDocument::VersionedTextDocumentIdentifier
    edits::Vector{TextEdit}
end

mutable struct WorkspaceEdit
    changes::Union{Any,Missing}
    documentChanges::Union{Vector{TextDocumentEdit},Missing}
end

@dict_readable struct DidOpenTextDocumentParams
    textDocument::TextDocumentItem
end

@dict_readable struct TextDocumentContentChangeEvent 
    range::Union{Range,Missing}
    rangeLength::Union{Int,Missing}
    text::String
end

@dict_readable struct DidChangeTextDocumentParams
    textDocument::VersionedTextDocumentIdentifier
    contentChanges::Vector{TextDocumentContentChangeEvent}
end

@dict_readable struct DidSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
    text::Union{String,Missing}
end

@dict_readable struct DidCloseTextDocumentParams
    textDocument::TextDocumentIdentifier
end

const TextDocumentSaveReason = Int
const TextDocumentSaveReasons = Dict(1 => "Manual", 2 => "AfterDelay", 3 => "FocusOut")

@dict_readable struct WillSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
    reason::TextDocumentSaveReason
end



