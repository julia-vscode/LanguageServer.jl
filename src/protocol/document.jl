type TextDocumentIdentifier
    uri::DocumentUri
end

TextDocumentIdentifier(d::Dict) = TextDocumentIdentifier(d["uri"])


type TextDocumentItem
    uri::DocumentUri
    languageId::String
    version::Int
    text::String
end

TextDocumentItem(d::Dict) = TextDocumentItem(d["uri"], d["languageId"], d["version"], d["text"])


type VersionedTextDocumentIdentifier
    uri::DocumentUri
    version::Int
end

VersionedTextDocumentIdentifier(d::Dict) = VersionedTextDocumentIdentifier(d["uri"], d["version"])


type TextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    position::Position
end

TextDocumentPositionParams(d::Dict) = TextDocumentPositionParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]))


type DocumentFilter
    language::Nullable{String}
    scheme::Nullable{String}
    pattern::Nullable{String}
end

function DocumentFilter(d::Dict)
    language = haskeynotnull(d, "language") ? d["language"] : Nullable{String}()
    scheme = haskeynotnull(d, "scheme") ? d["scheme"] : Nullable{String}()
    pattern = haskeynotnull(d, "pattern") ? d["pattern"] : Nullable{String}()
    return DocumentFilter(language, scheme, pattern)
end

const DocumentSelector = Vector{DocumentFilter}

type TextDocumentRegistrationOptions
    documentSelector::DocumentSelector
end

type TextDocumentEdit
    textDocument::VersionedTextDocumentIdentifier
    edits::Vector{TextEdit}
end


type WorkspaceEdit
    changes
    documentChanges::Vector{TextDocumentEdit}
end


type DidOpenTextDocumentParams
    textDocument::TextDocumentItem
end

DidOpenTextDocumentParams(d::Dict) = DidOpenTextDocumentParams(TextDocumentItem(d["textDocument"]))


type TextDocumentContentChangeEvent 
    range::Range
    rangeLength::Int
    text::String
end

function TextDocumentContentChangeEvent(d::Dict)
      if length(d) == 1
          text = d["text"]
          rangeLength = length(text)
          lines = split(text, "\n")
          TextDocumentContentChangeEvent(Range(0, 0, length(lines) - 1, length(lines[end]) - 1), rangeLength, text)
      else
          TextDocumentContentChangeEvent(Range(d["range"]), d["rangeLength"], d["text"])
      end
  end


type DidChangeTextDocumentParams
    textDocument::VersionedTextDocumentIdentifier
    contentChanges::Vector{TextDocumentContentChangeEvent}
end

DidChangeTextDocumentParams(d::Dict) = DidChangeTextDocumentParams(VersionedTextDocumentIdentifier(d["textDocument"]), TextDocumentContentChangeEvent.(d["contentChanges"]))


type DidSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
end

DidSaveTextDocumentParams(d::Dict) = DidSaveTextDocumentParams(TextDocumentIdentifier(d["textDocument"]))



type DidCloseTextDocumentParams
    textDocument::TextDocumentIdentifier
end

DidCloseTextDocumentParams(d::Dict) = DidCloseTextDocumentParams(TextDocumentIdentifier(d["textDocument"]))


const FileChangeType = Dict("Created" => 1, "Changed" => 2, "Deleted" => 3)
const FileChangeType_Created = 1
const FileChangeType_Changed = 2
const FileChangeType_Deleted = 3

type FileEvent
    uri::String
    _type::Int
end
FileEvent(d::Dict) = FileEvent(d["uri"], d["type"])

type DidChangeWatchedFilesParams
    changes::Vector{FileEvent}
end

function DidChangeWatchedFilesParams(d::Dict)
    DidChangeWatchedFilesParams(FileEvent.(d["changes"]))
end
