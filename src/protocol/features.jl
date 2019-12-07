struct PublishDiagnosticsParams <: Outbound
    uri::DocumentUri
    diagnostics::Vector{Diagnostic}
end

##############################################################################
# Completions

const CompletionTriggerKind = Int
const CompletionTriggerKinds = Dict(1 => "Invoked", 2 => "TriggerCharacter", 3 => "TriggerForIncompleteCompletion")
@dict_readable struct CompletionContext
    triggerKind::CompletionTriggerKind
    triggerCharacter::Union{String,Missing}
end

@dict_readable struct CompletionParams
    textDocument::TextDocumentIdentifier
    position::Position
    context::Union{CompletionContext,Missing}
end

@dict_readable struct CompletionItem <: Outbound
    label::String
    kind::Union{Int,Missing}
    detail::Union{String,Missing}
    documentation::Union{String,MarkupContent,Missing}
    deprecated::Union{Bool,Missing}
    preselect::Union{Bool,Missing}
    sortText::Union{String,Missing}
    filterText::Union{String,Missing}
    insertText::Union{String,Missing}
    insertTextFormat::Union{Int,Missing}
    textEdit::Union{TextEdit,Missing}
    additionalTextEdits::Union{Vector{TextEdit},Missing}
    commitCharacters::Union{Vector{String},Missing}
    command::Union{Command,Missing}
    data::Union{Any,Missing}
end
CompletionItem(label, kind, documentation, textEdit) = CompletionItem(label, kind, missing, documentation, missing, missing, missing, missing, missing, 2, textEdit, missing, missing, missing, missing)

struct CompletionList <: Outbound
    isIncomplete::Bool
    items::Vector{CompletionItem}
end

# const CompletionItemKind = Dict{String,Int}(
#     "Text" => 1,
#     "Method" => 2,
#     "Function" => 3,
#     "Constructor" => 4,
#     "Field" => 5,
#     "Variable" => 6,
#     "Class" => 7,
#     "Interface" => 8,
#     "Module" => 9,
#     "Property" => 10,
#     "Unit" => 11,
#     "Value" => 12,
#     "Enum" => 13,
#     "Keyword" => 14,
#     "Snippet" => 15,
#     "Color" => 16,
#     "File" => 17,
#     "Reference" => 18,
#     "Folder" => 19,
#     "EnumMember" => 20,
#     "Constant" => 21,
#     "Struct" => 22,
#     "Event" => 23,
#     "Operator" => 24,
#     "TypeParameter" => 25)

struct CompletionRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    triggerCharacters::Union{Vector{String},Missing}
    allCommitCharacters::Union{Vector{String},Missing}
    resolveProvider::Union{Bool,Missing}
end

##############################################################################
# Hover

struct Hover <: Outbound
    contents::Union{MarkedString,Vector{MarkedString},MarkupContent}
    range::Union{Range,Missing}
end

##############################################################################
# Signature help

struct ParameterInformation <: Outbound
    label::Union{String,Tuple{Int,Int}}
    documentation::Union{String,MarkupContent,Missing}
end

struct SignatureInformation <: Outbound
    label::String
    documentation::Union{String,MarkedString,Missing}
    parameters::Union{Vector{ParameterInformation},Missing}
end

struct SignatureHelp <: Outbound
    signatures::Vector{SignatureInformation}
    activeSignature::Union{Int,Missing}
    activeParameter::Union{Int,Missing}
end

struct SignatureHelpRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    triggerCharacters::Union{Vector{String},Missing}
end

##############################################################################
# References

@dict_readable struct ReferenceContext
    includeDeclaration::Bool
end

@dict_readable struct ReferenceParams
    textDocument::TextDocumentIdentifier
    position::Position
    context::ReferenceContext
end

##############################################################################
# Highlighting

const DocumentHighlightKind = Int
const DocumentHighlightKinds = Dict("Text" => 1, "Read" => 2, "Write" => 3)

struct DocumentHighlight <: Outbound
    range::Range
    kind::Union{DocumentHighlightKind, Missing}
end

##############################################################################
# Symbols 

@dict_readable struct DocumentSymbolParams 
    textDocument::TextDocumentIdentifier 
end 

const SymbolKind = Int
const SymbolKinds = Dict{String,Int}(
    "File" => 1,
    "Module" => 2,
    "Namespace" => 3,
    "Package" => 4,
    "Class" => 5,
    "Method" => 6,
    "Property" => 7,
    "Field" => 8,
    "Constructor" => 9,
    "Enum" => 10,
    "Interface" => 11,
    "Function" => 12,
    "Variable" => 13,
    "Constant" => 14,
    "String" => 15,
    "Number" => 16,
    "Boolean" => 17,
    "Array" => 18,
    "Object" => 19,
    "Key" => 20,
    "Null" => 21,
    "EnumMember" => 22,
    "Struct" => 23,
    "Event" => 24,
    "Operator" => 25,
    "TypeParameter" => 26
)


struct SymbolInformation <: Outbound
    name::String 
    kind::SymbolKind
    deprecated::Union{Nothing,Bool}
    location::Location 
    containerName::Union{Nothing,String}
end

struct DocumentSymbol <: Outbound
    name::String
    detail::Union{String,Missing}
    kind::SymbolKind
    deprecated::Union{Bool,Missing}
    range::Range
    selectionRange::Range
    children::Union{Vector{DocumentSymbol},Missing}
end



@dict_readable struct WorkspaceSymbolParams 
    query::String 
end 

import Base.==  
==(x::CompletionItem, y::CompletionItem) = x.label == y.label
==(m1::MarkedString, m2::MarkedString) = m1.language == m2.language && m1.value == m2.value

##############################################################################
# Code Action

@dict_readable struct CodeActionContext
    diagnostics::Vector{Diagnostic}
    only::Union{Vector{CodeActionKind}, Missing}
end

@dict_readable struct CodeActionParams
    textDocument::TextDocumentIdentifier
    range::Range
    context::CodeActionContext
end

struct CodeAction <: Outbound
    title::String
    kind::Union{CodeActionKind,Missing}
    diagnostics::Union{Vector{Diagnostic},Missing}
    edit::Union{WorkspaceEdit,Missing}
    command::Union{Command,Missing}
end

struct CodeActionRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    codeActionKinds::Union{Vector{CodeActionKind},Missing}
end

##############################################################################
# Code Lens

@dict_readable struct CodeLensParams
    textDocument::TextDocumentIdentifier
end

struct CodeLens <: Outbound
    range::Range
    command::Union{Command,Missing}
    data::Union{Any,Missing}
end

struct CodeLensRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    resolveProvider::Union{Bool,Missing}
end

##############################################################################
# Document Link Provider

@dict_readable struct DocumentLinkParams
    textDocument::TextDocumentIdentifier
end

struct DocumentLink <: Outbound
    range::Range
    target::Union{String,Missing}
    data::Union{Any,Missing}
end

struct DocumentLinkRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    resolveProvider::Union{Bool,Missing}
end

##############################################################################
# Document Colour

@dict_readable struct DocumentColorParams
    textDocument::TextDocumentIdentifier
end

struct Color <: Outbound
    red::Float64
    green::Float64
    blue::Float64
    alpha::Float64
end

struct ColorInformation <: Outbound
    range::Range
    color::Color
end

@dict_readable struct ColorPresentationParams
    textDocument::TextDocumentIdentifier
    color::Color
    range::Range
end

struct ColorPresentaiton <: Outbound
    label::String
    textEdit::Union{TextEdit,Missing}
    additionalTextEdits::Union{Vector{TextEdit},Missing}
end

##############################################################################
# Formatting

@dict_readable struct FormattingOptions
    tabSize::Integer
    insertSpaces::Bool
end

@dict_readable struct DocumentFormattingParams
    textDocument::TextDocumentIdentifier
    options::FormattingOptions
end


@dict_readable struct DocumentRangeFormattingParams
    textDocument::TextDocumentIdentifier
    range::Range
    options::FormattingOptions
end

@dict_readable struct DocumentOnTypeFormattingParams
    textDocument::TextDocumentIdentifier
    position::Position
    ch::String
    options::FormattingOptions
end

struct DocumentOnTypeFormattingRegistrationOptions <: Outbound
    documentSelector::DocumentSelector
    firstTriggerCharacter::String
    moreTriggerCharacer::Vector{String}
end

##############################################################################
# Rename

@dict_readable struct RenameParams
    textDocument::TextDocumentIdentifier
    position::Position
    newName::String
end

struct RenameRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    prepareProvider::Union{Bool,Missing}
end

##############################################################################
# Folding

@dict_readable struct FoldingRangeParams
    textDocument::TextDocumentIdentifier
end

const FoldingRangeKind = String
const FoldingRangeKinds = ("comment", "imports", "region")

struct FoldingRange <: Outbound
    startLine::Int
    startCharacter::Union{Int,Missing}
    endLine::Int
    endCharacter::Union{Int,Missing}
    kind::Union{FoldingRangeKind,Missing}
end

##############################################################################
# Execute command

@dict_readable struct ExecuteCommandParams
    command::String
    arguments::Union{Vector{Any},Missing}
end

mutable struct ExecuteCommandRegistrationOptions
    commands::Vector{String}
end

##############################################################################

struct ApplyWorkspaceEditParams <: Outbound
    label::Union{String,Missing}
    edit::WorkspaceEdit
end

@dict_readable struct ApplyWorkspaceEditResponse
    applied::Bool
    failureReason::Union{String,Missing}
end
