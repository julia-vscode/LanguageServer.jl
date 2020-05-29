# Document
@dict_readable struct DocumentFormattingClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct DocumentFormattingOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct DocumentFormattingRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct FormattingOptions <: Outbound
    tabSize::Integer
    insertSpaces::Bool
    trimTrailingWhitespace::Union{Bool,Missing}
    insertFinalNewline::Union{Bool,Missing}
    trimFinalNewlines::Union{Bool,Missing}
end

@dict_readable struct DocumentFormattingParams <: Outbound
    textDocument::TextDocumentIdentifier
    options::FormattingOptions
end


# Range
@dict_readable struct DocumentRangeFormattingClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct DocumentRangeFormattingOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct DocumentRangeFormattingRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct DocumentRangeFormattingParams
    textDocument::TextDocumentIdentifier
    range::Range
    options::FormattingOptions
end


# On type
@dict_readable struct DocumentOnTypeFormattingClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct DocumentOnTypeFormattingOptions <: Outbound
    firstTriggerCharacter::String
    moreTriggerCharacters::Union{Vector{String},Missing}
end

struct DocumentOnTypeFormattingRegistrationOptions <: Outbound
    documentSelector::DocumentSelector
    firstTriggerCharacter::String
    moreTriggerCharacer::Vector{String}
end

@dict_readable struct DocumentOnTypeFormattingParams
    textDocument::TextDocumentIdentifier
    position::Position
    ch::String
    options::FormattingOptions
end
