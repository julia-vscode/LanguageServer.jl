struct PublishDiagnosticsParams <: Outbound
    uri::DocumentUri
    version::Union{Int,Missing}
    diagnostics::Vector{Diagnostic}
end

import Base.==
==(x::CompletionItem, y::CompletionItem) = x.label == y.label
==(m1::MarkedString, m2::MarkedString) = m1.language == m2.language && m1.value == m2.value

##############################################################################
# Code Action
const CodeActionKind = String
const CodeActionKinds = (Empty = "",
                         QuickFix = "quickfix",
                         Refactor = "refactor",
                         RefactorExtract = "refactor.extract",
                         RefactorInline = "refactor.inline",
                         RefactorRewrite = "refactor.rewrite",
                         Source = "source",
                         SourceOrganizeImports = "source.organiseImports")

@dict_readable struct CodeActionKindCapabilities
    valueSet::Vector{CodeActionKind}
end

@dict_readable struct CodeActionLiteralCapabilities
    codeActionKind::CodeActionKindCapabilities
end

@dict_readable struct CodeActionClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    codeActionLiteralSupport::Union{CodeActionLiteralCapabilities,Missing}
    isPreferredSupport::Union{Bool,Missing}
end

struct CodeActionOptions <: Outbound
    codeActionKinds::Union{Vector{CodeActionKind},Missing}
    workDoneProgress::Union{Bool,Missing}
end

struct CodeActionRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    codeActionKinds::Union{Vector{CodeActionKind},Missing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct CodeActionContext <: Outbound
    diagnostics::Vector{Diagnostic}
    only::Union{Vector{CodeActionKind},Missing}
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
    isPreferred::Union{Bool,Missing}
    edit::Union{WorkspaceEdit,Missing}
    command::Union{Command,Missing}
end


##############################################################################
# Code Lens
@dict_readable struct CodeLensClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct CodeLensOptions <: Outbound
    resolveProvider::Union{Bool,Missing}
    workDoneProgress::Union{Bool,Missing}
end

struct CodeLensRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    resolveProvider::Union{Bool,Missing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct CodeLensParams
    textDocument::TextDocumentIdentifier
end

struct CodeLens <: Outbound
    range::Range
    command::Union{Command,Missing}
    data::Union{Any,Missing}
end


##############################################################################
# Document Link Provider
@dict_readable struct DocumentLinkClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    tooltipSupport::Union{Bool,Missing}
end

struct DocumentLinkOptions <: Outbound
    resolveProvider::Union{Bool,Missing}
    workDoneProgress::Union{Bool,Missing}
end

struct DocumentLinkRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    resolveProvider::Union{Bool,Missing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct DocumentLinkParams
    textDocument::TextDocumentIdentifier
end

struct DocumentLink <: Outbound
    range::Range
    target::Union{String,Missing}
    tooltip::Union{String,Missing}
    data::Union{Any,Missing}
end

##############################################################################
# Document Colour

@dict_readable struct DocumentColorClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct DocumentColorOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct DocumentColorRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    id::Union{String,Missing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct DocumentColorParams <: Outbound
    textDocument::TextDocumentIdentifier
    workDoneToken::Union{ProgressToken,Missing}
    partialResultToken::Union{ProgressToken,Missing}
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


##############################################################################
# Rename

@dict_readable struct RenameClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    prepareSupport::Union{Bool,Missing}
end

struct RenameOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
    prepareProvider::Union{Bool,Missing}
end

struct RenameRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
    prepareProvider::Union{Bool,Missing}
end

@dict_readable struct RenameParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken,Missing}
    newName::String
end

@dict_readable struct PrepareRenameParams
    textDocument::TextDocumentIdentifier
    position::Position
end


##############################################################################
# Folding
const FoldingRangeKind = String
const FoldingRangeKinds = (Comment = "comment",
                           Imports = "imports",
                           Region = "region")

@dict_readable struct FoldingRangeClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    rangeLimit::Union{Int,Missing}
    lineFoldingOnly::Union{Bool,Missing}
end

struct FoldingRangeOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct FoldingRangeRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
    id::Union{String,Missing}
end

@dict_readable struct FoldingRangeParams <: Outbound
    textDocument::TextDocumentIdentifier
    workDoneToken::Union{ProgressToken,Missing}
    partialResultToken::Union{ProgressToken,Missing}
end

struct FoldingRange <: Outbound
    startLine::Int
    startCharacter::Union{Int,Missing}
    endLine::Int
    endCharacter::Union{Int,Missing}
    kind::Union{FoldingRangeKind,Missing}
end

##############################################################################
# Selection Range
@dict_readable struct SelectionRangeClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct SelectionRangeOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct SelectionRangeRegistrationOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
    documentSelector::Union{DocumentSelector,Nothing}
    id::Union{String,Missing}
end

@dict_readable struct SelectionRangeParams <: Outbound
    workDoneToken::Union{ProgressToken,Missing}
    partialResultToken::Union{ProgressToken,Missing}
    textDocument::TextDocumentIdentifier
    positions::Vector{Position}
end

struct SelectionRange <: Outbound
    range::Range
    parent::Union{SelectionRange,Missing}
end


##############################################################################
# Execute command
@dict_readable struct ExecuteCommandClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct ExecuteCommandOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
    commands::Vector{String}
end

mutable struct ExecuteCommandRegistrationOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
    commands::Vector{String}
end

@dict_readable struct ExecuteCommandParams <: Outbound
    workDoneToken::Union{ProgressToken,Missing}
    command::String
    arguments::Union{Vector{Any},Missing}
end


##############################################################################

struct ApplyWorkspaceEditParams <: Outbound
    label::Union{String,Missing}
    edit::WorkspaceEdit
end

@dict_readable struct ApplyWorkspaceEditResponse <: Outbound
    applied::Bool
    failureReason::Union{String,Missing}
end
