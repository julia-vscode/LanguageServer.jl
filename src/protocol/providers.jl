type PublishDiagnosticsParams
    uri::String
    diagnostics::Vector{Diagnostic}
end


# const CompletionItemKind = Dict("Text" => 1,
#                                 "Method" => 2,
#                                 "Function" => 3,
#                                 "Constructor" => 4,
#                                 "Field" => 5,
#                                 "Variable" => 6,
#                                 "Class" => 7,
#                                 "Interface" => 8,
#                                 "Module" => 9,
#                                 "Property" => 10,
#                                 "Unit" => 11,
#                                 "Value" => 12,
#                                 "Enum" => 13,
#                                 "Keyword" => 14,
#                                 "Snippet" => 15,
#                                 "Color" => 16,
#                                 "File" => 17,
#                                 "Reference" => 18)

type CompletionItem
    label::String
    kind::Int
    documentation::String
    textEdit::TextEdit
    additionalTextEdits::Vector{TextEdit}
end
# Make more specific if we extend completions (i.e. brackets for functions w/ arg placements)
import Base.==  
==(x::CompletionItem, y::CompletionItem) = x.label == y.label

type CompletionList
    isIncomplete::Bool
    items::Vector{CompletionItem}
end


type MarkedString
    language::String
    value::AbstractString
end
MarkedString(x) = MarkedString("julia", string(x))
Base.hash(x::MarkedString) = hash(x.value) # for unique

type Hover
    contents::Vector{Union{AbstractString,MarkedString}}
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

type SignatureHelpRegistrationOptions end


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


const DocumentHighlightKind = Dict("Text" => 1, "Read" => 2, "Write" => 3)

type DocumentHighlight
    range::Range
    kind::Integer
end

# Document Symbols Provider
type DocumentSymbolParams 
    textDocument::TextDocumentIdentifier 
end 

DocumentSymbolParams(d::Dict) = DocumentSymbolParams(TextDocumentIdentifier(d["textDocument"])) 

# const SymbolKind = Dict("File" => 1,
#                         "Module" => 2,
#                         "Namespace" => 3,
#                         "Package" => 4,
#                         "Class" => 5,
#                         "Method" => 6,
#                         "Property" => 7,
#                         "Field" => 8,
#                         "Constructor" => 9,
#                         "Enum" => 10,
#                         "Interface" => 11,
#                         "Function" => 12,
#                         "Variable" => 13,
#                         "Constant" => 14,
#                         "String" => 15,
#                         "Number" => 16,
#                         "Boolean" => 17,
#                         "Array" => 18)

type SymbolInformation 
    name::String 
    kind::Int 
    location::Location 
    containername::String
end 
SymbolInformation(name::String, kind::Int, location::Location) = SymbolInformation(name, kind, location, "")

type WorkspaceSymbolParams 
    query::String 
end 
WorkspaceSymbolParams(d::Dict) = WorkspaceSymbolParams(d["query"])


# CodeAction

type CodeActionContext
    diagnostics::Vector{Diagnostic}
end
CodeActionContext(d::Dict) = CodeActionContext(Diagnostic.(d["diagnostics"]))

type CodeActionParams
    textDocument::TextDocumentIdentifier
    range::Range
    context::CodeActionContext
end
CodeActionParams(d::Dict) = CodeActionParams(TextDocumentIdentifier(d["textDocument"]), Range(d["range"]), CodeActionContext(d["context"]))

# Code Lens
type CodeLensParams
    textDocument::TextDocumentIdentifier
end
CodeLensParams(d::Dict) = CodeLensParams(TextDocumentIdentifier(d["textDocument"]))

type CodeLens
    range::Range
    command::Command
    data::Any
end

type CodeLensRegistrationOptions
    resolveProvider::Bool
end


# Document Link Provider

type DocumentLinkParams
    textDocument::TextDocumentIdentifier
end

DocumentLinkParams(d::Dict) = DocumentLinkParams(TextDocumentIdentifier(d["textDocument"]))

type DocumentLink
    range::Range
    target::String
end



# Document Formatting

type FormattingOptions
    tabSize::Integer
    insertSpaces::Bool
end
FormattingOptions(d::Dict) = FormattingOptions(d["tabSize"], d["insertSpaces"])

type DocumentFormattingParams
    textDocument::TextDocumentIdentifier
    options::FormattingOptions
end
DocumentFormattingParams(d::Dict) = DocumentFormattingParams(TextDocumentIdentifier(d["textDocument"]), FormattingOptions(d["options"]))

type DocumentRangeFormattingParams
    textDocument::TextDocumentIdentifier
    range::Range
    options::FormattingOptions
end

type DocumentOnTypeFormattingParams
    textDocument::TextDocumentIdentifier
    position::Position
    ch::String
    options::FormattingOptions
end

type DocumentOnTypeFormattingRegistrationOptions
    documentSelector::DocumentSelector
    firstTriggerCharacter::String
    moreTriggerCharacer::Vector{String}
end


# Rename

type RenameParams
    textDocument::TextDocumentIdentifier
    position::Position
    newName::String
end


# Execute Command

type ExecuteCommandParams
    command::String
    arguments::Vector{Any}
end

type ExecuteCommandRegistrationOptions
    commands::Vector{String}
end


# WorkspaceEdit

type ApplyWorkspaceEditParams
    edit::WorkspaceEdit
end

type ApplyWorkspaceEditResponse
    applied::Bool
end
ApplyWorkspaceEditResponse(d::Dict) = ApplyWorkspaceEditResponse(d["applied"])
