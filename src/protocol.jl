# Position
type Position
    line::Int
    character::Int

    function Position(line::Integer, character::Integer;one_based=false)
        if one_based
            return new(line-1, character-1)
        else
            return new(line, character)
        end
    end
end
Position(d::Dict) = Position(d["line"], d["character"])
Position(line) = Position(line,0)

type Range
    start::Position
    stop::Position # mismatch between vscode-ls protocol naming (should be 'end')
end

function JSON._writejson(io::IO, state::JSON.State, a::Range)
    Base.print(io,"{\"start\":")
    JSON._writejson(io,state,a.start)
    Base.print(io,",\"end\":")
    JSON._writejson(io,state,a.stop)
    Base.print(io,"}")
end

Range(d::Dict) = Range(Position(d["start"]), Position(d["end"]))
Range(line) = Range(Position(line), Position(line))
Range(l0, c0, l1, c1) = Range(Position(l0, c0), Position(l1, c1))

type Location
    uri::String
    range::Range
end
Location(d::Dict) = Location(d["uri"], Range(d["range"]))
Location(f::String, line) = Location(f, Range(line))

type MarkedString
    language::String
    value::AbstractString
end
MarkedString(x) = MarkedString("julia", string(x))

type Hover
    contents::Vector{Union{AbstractString,MarkedString}}
end

type TextEdit
    range::Range
    newText::String
end

type CompletionItem
    label::String
    kind::Int
    documentation::String
    textEdit::TextEdit
    additionalTextEdits::Vector{TextEdit}
end

type CompletionList
    isIncomplete::Bool
    items::Vector{CompletionItem}
end

type Diagnostic
    range::Range
    severity::Int
    code::String
    source::String
    message::String
end

type PublishDiagnosticsParams
    uri::String
    diagnostics::Vector{Diagnostic}
end

type CompletionOptions 
    resolveProvider::Bool
    triggerCharacters::Vector{String}
end

type SignatureHelpOptions
    triggerCharacters::Vector{String}
end

type DocumentLinkOptions
    resolveProvider::Bool
end

type ServerCapabilities
    textDocumentSync::Int
    hoverProvider::Bool
    completionProvider::CompletionOptions
    definitionProvider::Bool
    signatureHelpProvider::SignatureHelpOptions
    documentSymbolProvider::Bool
    referencesProvider::Bool
    workspaceSymbolProvider::Bool
    documentLinkProvider::DocumentLinkOptions
    # documentHighlightProvider::Bool
    # codeActionProvider::Bool
    # codeLensProvider::CodeLensOptions
    # documentFormattingProvider::Bool
    # documentRangeFormattingProvider::Bool
    # documentOnTypeFormattingProvider::DocumentOnTypeFormattingOptions
    # renameProvider::Bool
end

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
    DidChangeWatchedFilesParams(map(i->FileEvent(i),d["changes"]))
end

type InitializeResult
    capabilities::ServerCapabilities
end

type ParameterInformation
    label::String
    #documentation::String
end

type SignatureInformation
    label::String
    documentation::String
    parameters::Vector{ParameterInformation}
end

type SignatureHelp
    signatures::Vector{SignatureInformation}
    activeSignature::Int
    activeParameter::Int
end

# TextDocument

type TextDocumentIdentifier
    uri::String
end
TextDocumentIdentifier(d::Dict) = TextDocumentIdentifier(d["uri"])


type VersionedTextDocumentIdentifier
    uri::String
    version::Int
end
VersionedTextDocumentIdentifier(d::Dict) = VersionedTextDocumentIdentifier(d["uri"], d["version"])



type TextDocumentContentChangeEvent 
    range::Range
    rangeLength::Int
    text::String
end
TextDocumentContentChangeEvent(d::Dict) = TextDocumentContentChangeEvent(Range(d["range"]), d["rangeLength"], d["text"])



type DidChangeTextDocumentParams
    textDocument::VersionedTextDocumentIdentifier
    contentChanges::Vector{TextDocumentContentChangeEvent}
end
DidChangeTextDocumentParams(d::Dict) = DidChangeTextDocumentParams(VersionedTextDocumentIdentifier(d["textDocument"]),TextDocumentContentChangeEvent.(d["contentChanges"]))


type TextDocumentItem
    uri::String
    languageId::String
    version::Int
    text::String
end
TextDocumentItem(d::Dict) = TextDocumentItem(d["uri"], d["languageId"], d["version"], d["text"])


type TextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    position::Position
end
TextDocumentPositionParams(d::Dict) = TextDocumentPositionParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]))

type ReferenceContext
    includeDeclaration::Bool
end
ReferenceContext(d::Dict) = ReferenceContext(d["includeDeclaration"] == "true")

type ReferenceParams
    textDocument::TextDocumentIdentifier
    position::Position
    context::ReferenceContext
end
ReferenceParams(d::Dict) = ReferenceParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]), ReferenceContext(d["context"]))

type DidOpenTextDocumentParams
    textDocument::TextDocumentItem
end
DidOpenTextDocumentParams(d::Dict) = DidOpenTextDocumentParams(TextDocumentItem(d["textDocument"]))

type DidCloseTextDocumentParams
    textDocument::TextDocumentIdentifier
end
DidCloseTextDocumentParams(d::Dict) = DidCloseTextDocumentParams(TextDocumentIdentifier(d["textDocument"]))

type DidSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
end
DidSaveTextDocumentParams(d::Dict) = DidSaveTextDocumentParams(TextDocumentIdentifier(d["textDocument"]))

type CancelParams
    id::Union{String,Int64}
end
CancelParams(d::Dict) = CancelParams(d["id"])

type DocumentSymbolParams 
    textDocument::TextDocumentIdentifier 
end 
DocumentSymbolParams(d::Dict) = DocumentSymbolParams(TextDocumentIdentifier(d["textDocument"])) 

type DocumentLinkParams
    textDocument::TextDocumentIdentifier
end
DocumentLinkParams(d::Dict) = DocumentLinkParams(TextDocumentIdentifier(d["textDocument"]))

type WorkspaceSymbolParams 
    query::String 
end 
WorkspaceSymbolParams(d::Dict) = WorkspaceSymbolParams(d["query"])

function Message(t::Int, text::AbstractString)
    Dict("jsonrpc"=>"2.0", "method"=>"window/showMessage", "params"=>Dict("type"=>t, "message"=>text))
end