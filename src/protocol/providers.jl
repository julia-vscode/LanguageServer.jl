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
    insertTextFormat::Union{Nothing,Int}
end

mutable struct CompletionList
    isIncomplete::Bool
    items::Vector{CompletionItem}
end

@enum(CompletionTriggerKind, Invoked = 1, TriggerCharacter = 2, TriggerForIncompleteCompletion = 3)

@json_read mutable struct CompletionContext
    triggerKind::CompletionTriggerKind
    triggerCharacter::Union{Nothing,String}
end

@json_read mutable struct CompletionParams
    textDocument::TextDocumentIdentifier
    position::Position
    context::Union{Nothing,CompletionContext}
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


@json_read mutable struct ReferenceContext
    includeDeclaration::Bool
end

@json_read mutable struct ReferenceParams
    textDocument::TextDocumentIdentifier
    position::Position
    context::ReferenceContext
end

mutable struct DocumentHighlight
    range::Range
    kind::Integer
end

# Document Symbols Provider
@json_read mutable struct DocumentSymbolParams 
    textDocument::TextDocumentIdentifier 
end 

mutable struct SymbolInformation 
    name::String 
    kind::Int 
    deprecated::Union{Nothing,Bool}
    location::Location 
    containerName::Union{Nothing,String}
end 

@json_read mutable struct WorkspaceSymbolParams 
    query::String 
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
==(m1::MarkedString, m2::MarkedString) = m1.language == m2.language && m1.value == m2.value


# ReferenceContext(d::Dict) = ReferenceContext(d["includeDeclaration"] == "true")
# ReferenceParams(d::Dict) = ReferenceParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]), ReferenceContext(d["context"]))
# DocumentSymbolParams(d::Dict) = DocumentSymbolParams(TextDocumentIdentifier(d["textDocument"])) 

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


@json_read mutable struct CodeActionContext
    diagnostics::Vector{Diagnostic}
end

@json_read mutable struct CodeActionParams
    textDocument::TextDocumentIdentifier
    range::Range
    context::CodeActionContext
end

# Code Lens
@json_read mutable struct CodeLensParams
    textDocument::TextDocumentIdentifier
end

mutable struct CodeLens
    range::Range
    command::Command
    data::Any
end

@json_read mutable struct CodeLensRegistrationOptions
    resolveProvider::Bool
end


# Document Link Provider

@json_read mutable struct DocumentLinkParams
    textDocument::TextDocumentIdentifier
end



mutable struct DocumentLink
    range::Range
    target::String
end

@json_read mutable struct FormattingOptions
    tabSize::Integer
    insertSpaces::Bool
end

@json_read mutable struct DocumentFormattingParams
    textDocument::TextDocumentIdentifier
    options::FormattingOptions
end


@json_read mutable struct DocumentRangeFormattingParams
    textDocument::TextDocumentIdentifier
    range::Range
    options::FormattingOptions
end

@json_read mutable struct DocumentOnTypeFormattingParams
    textDocument::TextDocumentIdentifier
    position::Position
    ch::String
    options::FormattingOptions
end

@json_read mutable struct DocumentOnTypeFormattingRegistrationOptions
    documentSelector::DocumentSelector
    firstTriggerCharacter::String
    moreTriggerCharacer::Vector{String}
end

@json_read mutable struct RenameParams
    textDocument::TextDocumentIdentifier
    position::Position
    newName::String
end

@json_read mutable struct ExecuteCommandParams
    command::String
    arguments::Vector{Any}
end

@json_read mutable struct ExecuteCommandRegistrationOptions
    commands::Vector{String}
end

@json_read mutable struct ApplyWorkspaceEditParams
    label::Union{Nothing,String}
    edit::WorkspaceEdit
end

@json_read mutable struct ApplyWorkspaceEditResponse
    applied::Bool
end
