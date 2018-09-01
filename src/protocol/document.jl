@json_read mutable struct TextDocumentIdentifier
    uri::DocumentUri
end

@json_read mutable struct TextDocumentItem
    uri::DocumentUri
    languageId::String
    version::Int
    text::String
end

@json_read mutable struct VersionedTextDocumentIdentifier
    uri::DocumentUri
    version::Int
end

@json_read mutable struct TextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    position::Position
end

@json_read mutable struct DocumentFilter
    language::Union{Nothing,String}
    scheme::Union{Nothing,String}
    pattern::Union{Nothing,String}
end

const DocumentSelector = Vector{DocumentFilter}

mutable struct TextDocumentRegistrationOptions
    documentSelector::DocumentSelector
end


mutable struct TextDocumentChangeRegistrationOptions
    documentSelector::DocumentSelector
    syncKind::Int    
end

mutable struct TextDocumentEdit
    textDocument::VersionedTextDocumentIdentifier
    edits::Vector{TextEdit}
end

mutable struct WorkspaceEdit
    changes
    documentChanges::Union{Nothing,Vector{TextDocumentEdit}}
end

@json_read mutable struct DidOpenTextDocumentParams
    textDocument::TextDocumentItem
end

@json_read mutable struct TextDocumentContentChangeEvent 
    range::Union{Nothing,Range}
    rangeLength::Union{Nothing,Int}
    text::String
end

@json_read mutable struct DidChangeTextDocumentParams
    textDocument::VersionedTextDocumentIdentifier
    contentChanges::Vector{TextDocumentContentChangeEvent}
end

@json_read mutable struct DidSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
    text::Union{Nothing,String}
end

@json_read mutable struct DidCloseTextDocumentParams
    textDocument::TextDocumentIdentifier
end

mutable struct FileEvent
    uri::String
    _type::Int
end
FileEvent(d::Dict) = FileEvent(d["uri"], d["type"])

@json_read mutable struct DidChangeWatchedFilesParams
    changes::Vector{FileEvent}
end

mutable struct FileSystemWatcher
    globPattern::String
    kind::Union{Nothing,Int}
end

mutable struct DidChangeWatchedFilesRegistrationOptions
    watchers::Vector{FileSystemWatcher}
end

mutable struct WillSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
    reason::Int
end





# TextDocumentIdentifier(d::Dict) = TextDocumentIdentifier(d["uri"])

# TextDocumentItem(d::Dict) = TextDocumentItem(d["uri"], d["languageId"], d["version"], d["text"])

# VersionedTextDocumentIdentifier(d::Dict) = VersionedTextDocumentIdentifier(d["uri"], d["version"])

# TextDocumentPositionParams(d::Dict) = TextDocumentPositionParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]))

# function DocumentFilter(d::Dict)
#     language = haskeynotnull(d, "language") ? d["language"] : nothing
#     scheme = haskeynotnull(d, "scheme") ? d["scheme"] : nothing
#     pattern = haskeynotnull(d, "pattern") ? d["pattern"] : nothing
#     return DocumentFilter(language, scheme, pattern)
# end

# DidOpenTextDocumentParams(d::Dict) = DidOpenTextDocumentParams(TextDocumentItem(d["textDocument"]))

# function TextDocumentContentChangeEvent(d::Dict)
#       if length(d) == 1
#           text = d["text"]
#           rangeLength = length(text)
#           lines = split(text, "\n")
#           TextDocumentContentChangeEvent(Range(0, 0, length(lines) - 1, length(lines[end]) - 1), rangeLength, text)
#       else
#           TextDocumentContentChangeEvent(Range(d["range"]), d["rangeLength"], d["text"])
#       end
#   end

# DidChangeTextDocumentParams(d::Dict) = DidChangeTextDocumentParams(VersionedTextDocumentIdentifier(d["textDocument"]), TextDocumentContentChangeEvent.(d["contentChanges"]))

# DidSaveTextDocumentParams(d::Dict) = DidSaveTextDocumentParams(TextDocumentIdentifier(d["textDocument"]), get(d, "text", nothing))

# DidCloseTextDocumentParams(d::Dict) = DidCloseTextDocumentParams(TextDocumentIdentifier(d["textDocument"]))




# function DidChangeWatchedFilesParams(d::Dict)
#     DidChangeWatchedFilesParams(FileEvent.(d["changes"]))
# end


# WillSaveTextDocumentParams(d::Dict) = WillSaveTextDocumentParams(TextDocumentIdentifier(d["textDocument"]), d["reason"])
