mutable struct PublishDiagnosticsParams
    uri::String
    diagnostics::Vector{Diagnostic}
end

mutable struct MarkedString
    language::String
    value::AbstractString
end

mutable struct CompletionItem
    label::String
    kind::Int
    documentation::Union{String,MarkedString}
    textEdit::TextEdit
    additionalTextEdits::Vector{TextEdit}
end

mutable struct CompletionList
    isIncomplete::Bool
    items::Vector{CompletionItem}
end


mutable struct Hover
    contents::Vector{Union{AbstractString,MarkedString}}
end


mutable struct ParameterInformation
    label::String
    #documentation::String
end

mutable struct SignatureInformation
    label::String
    documentation::Union{String,MarkedString}
    parameters::Vector{ParameterInformation}
end

mutable struct SignatureHelp
    signatures::Vector{SignatureInformation}
    activeSignature::Int
    activeParameter::Int
end

mutable struct SignatureHelpRegistrationOptions end


mutable struct ReferenceContext
    includeDeclaration::Bool
end

mutable struct ReferenceParams
    textDocument::TextDocumentIdentifier
    position::Position
    context::ReferenceContext
end

mutable struct DocumentHighlight
    range::Range
    kind::Integer
end

# Document Symbols Provider
mutable struct DocumentSymbolParams 
    textDocument::TextDocumentIdentifier 
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


MarkedString(x) = MarkedString("julia", string(x))
Base.hash(x::MarkedString) = hash(x.value) # for unique


# Make more specific if we extend completions (i.e. brackets for functions w/ arg placements)
import Base.==  
==(x::CompletionItem, y::CompletionItem) = x.label == y.label



ReferenceContext(d::Dict) = ReferenceContext(d["includeDeclaration"] == "true")


ReferenceParams(d::Dict) = ReferenceParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]), ReferenceContext(d["context"]))


const DocumentHighlightKind = Dict("Text" => 1, "Read" => 2, "Write" => 3)

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

mutable struct SymbolInformation 
    name::String 
    kind::Int 
    location::Location 
    containername::String
end 
SymbolInformation(name::String, kind::Int, location::Location) = SymbolInformation(name, kind, location, "")

mutable struct WorkspaceSymbolParams 
    query::String 
end 
WorkspaceSymbolParams(d::Dict) = WorkspaceSymbolParams(d["query"])


# CodeAction

mutable struct CodeActionContext
    diagnostics::Vector{Diagnostic}
end
CodeActionContext(d::Dict) = CodeActionContext(Diagnostic.(d["diagnostics"]))

mutable struct CodeActionParams
    textDocument::TextDocumentIdentifier
    range::Range
    context::CodeActionContext
end
CodeActionParams(d::Dict) = CodeActionParams(TextDocumentIdentifier(d["textDocument"]), Range(d["range"]), CodeActionContext(d["context"]))

# Code Lens
mutable struct CodeLensParams
    textDocument::TextDocumentIdentifier
end
CodeLensParams(d::Dict) = CodeLensParams(TextDocumentIdentifier(d["textDocument"]))

mutable struct CodeLens
    range::Range
    command::Command
    data::Any
end

mutable struct CodeLensRegistrationOptions
    resolveProvider::Bool
end


# Document Link Provider

mutable struct DocumentLinkParams
    textDocument::TextDocumentIdentifier
end

DocumentLinkParams(d::Dict) = DocumentLinkParams(TextDocumentIdentifier(d["textDocument"]))

mutable struct DocumentLink
    range::Range
    target::String
end



# Document Formatting

mutable struct FormattingOptions
    tabSize::Integer
    insertSpaces::Bool
end
FormattingOptions(d::Dict) = FormattingOptions(d["tabSize"], d["insertSpaces"])

mutable struct DocumentFormattingParams
    textDocument::TextDocumentIdentifier
    options::FormattingOptions
end
DocumentFormattingParams(d::Dict) = DocumentFormattingParams(TextDocumentIdentifier(d["textDocument"]), FormattingOptions(d["options"]))

mutable struct DocumentRangeFormattingParams
    textDocument::TextDocumentIdentifier
    range::Range
    options::FormattingOptions
end

mutable struct DocumentOnTypeFormattingParams
    textDocument::TextDocumentIdentifier
    position::Position
    ch::String
    options::FormattingOptions
end

mutable struct DocumentOnTypeFormattingRegistrationOptions
    documentSelector::DocumentSelector
    firstTriggerCharacter::String
    moreTriggerCharacer::Vector{String}
end


# Rename

mutable struct RenameParams
    textDocument::TextDocumentIdentifier
    position::Position
    newName::String
end
RenameParams(d::Dict) = RenameParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]), d["newName"])


# Execute Command

mutable struct ExecuteCommandParams
    command::String
    arguments::Vector{Any}
end

mutable struct ExecuteCommandRegistrationOptions
    commands::Vector{String}
end


# WorkspaceEdit

mutable struct ApplyWorkspaceEditParams
    label::Union{Nothing,String}
    edit::WorkspaceEdit
end

mutable struct ApplyWorkspaceEditResponse
    applied::Bool
end
ApplyWorkspaceEditResponse(d::Dict) = ApplyWorkspaceEditResponse(d["applied"])
