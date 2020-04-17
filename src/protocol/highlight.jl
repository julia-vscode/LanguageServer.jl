const DocumentHighlightKind = Int
const DocumentHighlightKinds = (Text = 1,
                                Read = 2,
                                Write = 3)

@dict_readable struct DocumentHighlightClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
end

struct DocumentHighlightOptions <: Outbound
    workDoneProgress::Union{Bool, Missing}
end

struct DocumentHighlightRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector, Nothing}
    workDoneProgress::Union{Bool, Missing}
end

@dict_readable struct DocumentHighlightParams
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken, Missing}
    partialResultToken::Union{ProgressToken,Missing}
end

struct DocumentHighlight <: Outbound
    range::Range
    kind::Union{DocumentHighlightKind, Missing}
end